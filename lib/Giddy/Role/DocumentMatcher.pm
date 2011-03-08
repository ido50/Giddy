package Giddy::Role::DocumentMatcher;

use Any::Moose 'Role';
use namespace::autoclean;
use Data::Compare;
use DateTime::Format::W3CDTF;
use Try::Tiny;
use Carp;

requires 'path';
requires '_futil';
requires '_database';
requires '_spath';

=head1 NAME

Giddy::Role::DocumentMatcher - Provides query parsing and document matching for Giddy::Collection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 _match_by_name( $name, \%options )

=cut

sub _match_by_name {
	my ($self, $name, $opts) = @_;

	my @files = $opts->{working} ? $self->_futil->list_dir(File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath)) : $self->_database->_repo->run('ls-tree', '--name-only', $self->_spath ? 'HEAD:'.$self->_spath : 'HEAD:');
	my $cursor = Giddy::Cursor->new(_query => { name => $name, coll => $self, opts => $opts });

	# what kind of match are we performing? do we search for things
	# that start with $path, or do we search for $path anywhere?
	my $re = $name && $opts->{prefix} ? qr/^$name/ : $name ? qr/$name/ : qr//;

	foreach (@files) {
		if (m/$re/) {
			my $full_path = File::Spec->catfile($self->path, $_);
			my $search_path = ($full_path =~ m!^/(.+)$!)[0];

			if ($opts->{working}) {
				# what is the type of this thing?
				if (-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path) && -e File::Spec->catfile($self->_database->_repo->work_tree, $search_path, 'attributes.yaml')) {
					# this is a document directory
					$cursor->_add_result({ document_dir => $full_path });
				} elsif (!-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path)) {
					# this is a document file
					$cursor->_add_result({ document_file => $full_path });
				}
			} else {
				# what is the type of this thing?
				my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$search_path");
				if ($t eq 'tree') {
					# this is either a collection or a document
					if (grep {/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$search_path")) {
						# great, this is a document directory, let's add it
						$cursor->_add_result({ document_dir => $full_path });
					}
				} elsif ($t eq 'blob') {
					# cool, this is a document file
					$cursor->_add_result({ document_file => $full_path });
				}
			}
		}
	}

	return $cursor;
}

=head2 _match_by_query( [ \%query, \%options ] )

=cut

sub _match_by_query {
	my ($self, $query, $opts) = @_;

	$query ||= {};
	$opts ||= {};

	my $cursor = Giddy::Cursor->new(_query => { query => $query, coll => $self, opts => $opts });

	if ($opts->{working}) {
		foreach ($self->_futil->list_dir(File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath))) {
			my $fs_path = File::Spec->catfile($self->_database->_repo->work_tree, $self->_spath, $_);
			my $full_path = File::Spec->catfile($self->path, $_);

			# what is the type of this doc?
			my $t;
			if (-d $fs_path && -e File::Spec->catfile($fs_path, 'attributes.yaml')) {
				# this is a document dir
				my $doc = $self->_load_document_dir($full_path, 1);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_dir => $full_path });
					$cursor->_add_loaded($doc);
				}
			} elsif (!-d $fs_path) {
				# this is a document file
				my $doc = $self->_load_document_file($full_path, 1);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_dir => $full_path });
					$cursor->_add_loaded($doc);
				}
			}
		}
	} else {
		foreach ($self->_database->_repo->run('ls-tree', '--name-only', $self->_spath ? 'HEAD:'.$self->_spath : 'HEAD:')) {
			my $full_path = File::Spec->catfile($self->path, $_);
			my $search_path = ($full_path =~ m!^/(.+)$!)[0];

			# what is the type of this thing?
			my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$search_path");
			if ($t eq 'tree') {
				# this is either a collection or a document
				if (grep {/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$search_path")) {
					# great, this is a document directory, let's add it
					my $doc = $self->_load_document_dir($full_path);
					if ($self->_document_matches($doc, $query)) {
						$cursor->_add_result({ document_dir => $full_path });
						$cursor->_add_loaded($doc);
					}
				}
			} elsif ($t eq 'blob') {
				# cool, this is a document file
				my $doc = $self->_load_document_file($full_path);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_file => $full_path });
					$cursor->_add_loaded($doc);
				}
			}
		}
	}

	return $cursor;
}

=head2 _document_matches( \%doc, \%query )

=cut

sub _document_matches {
	my ($self, $doc, $query) = @_;

	croak "You must provide a document hash-ref."
		unless $doc && ref $doc eq 'HASH';

	$query ||= {}; # allow empty queries (document will match)

	# go over each key of the query
	foreach my $key (keys %$query) {
		my $value = $query->{$key};
		if ($key eq '$or' && ref $value eq 'ARRAY') {
			my $found;
			foreach (@$value) {
				next unless ref $_ eq 'HASH';
				my $ok = 1;
				while (my ($k, $v) = each %$_) {
					unless ($self->_attribute_matches($doc, $k, $v)) {
						undef $ok;
						last;
					}
				}
				if ($ok) { # document matches this criteria
					$found = 1;
					last;
				}
			}
			return unless $found;
		} else {
			return unless $self->_attribute_matches($doc, $key, $value);
		}
	}

	# if we've reached here, the document matches, so return true
	return 1;
}

=head2 _attributes_matches( \%doc, $key, $value )

=cut

sub _attribute_matches {
	my ($self, $doc, $key, $value) = @_;

	if (!ref $value) {	# if value is a scalar, we need to check for equality
					# (or, if the attribute is an array in the document,
					# we need to check the value exists in it)
		return unless $doc->{$key};
		if (ref $doc->{$key} eq 'ARRAY') { # check the array has the requested value
			return unless $self->_array_has_eq($value, $doc->{$key});
		} elsif (!ref $doc->{$key}) { # check the values are equal
			return unless $doc->{$key} eq $value;
		} else { # we can't compare a non-scalar to a scalar, so return false
			return;
		}
	} elsif (ref $value eq 'Regexp') {	# if the value is a regex, we need to check
						# for a match (or, if the attribute is an array
						# in the document, we need to check at least one
						# value in it matches it)
		return unless $doc->{$key};
		if (ref $doc->{$key} eq 'ARRAY') {
			return unless $self->_array_has_re($value, $doc->{$key});
		} elsif (!ref $doc->{$key}) { # check the values match
			return unless $doc->{$key} =~ $value;
		} else { # we can't compare a non-scalar to a scalar, so return false
			return;
		}
	} elsif (ref $value eq 'HASH') { # if the value is a hash, than it either contains
					 # advanced queries, or it's just a hash that we
					 # want the document to have as-is
		unless ($self->_has_adv_que($value)) {
			# value hash-ref doesn't have any advanced
			# queries, we need to check our document
			# has an attributes with exactly the same hash-ref
			# (and name of course)
			return unless Compare($value, $doc->{$key});
		} else {
			# value contains advanced queries,
			# we need to make sure our document has an
			# attribute with the same name that matches
			# all these queries
			foreach my $q (keys %$value) {
				my $term = $value->{$q};
				if ($q eq '$gt') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} > $term;
					} else {
						return unless $doc->{$key} gt $term;
					}
				} elsif ($q eq '$gte') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} >= $term;
					} else {
						return unless $doc->{$key} ge $term;
					}
				} elsif ($q eq '$lt') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} < $term;
					} else {
						return unless $doc->{$key} lt $term;
					}
				} elsif ($q eq '$gt') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} <= $term;
					} else {
						return unless $doc->{$key} le $term;
					}
				} elsif ($q eq '$ne') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} != $term;
					} else {
						return unless $doc->{$key} ne $term;
					}
				} elsif ($q eq '$exists') {
					if ($term) {
						return unless exists $doc->{$key};
					} else {
						return if exists $doc->{$key};
					}
				} elsif ($q eq '$mod' && ref $term eq 'ARRAY' && scalar @$term == 2) {
					return unless defined $doc->{$key} && $doc->{$key} =~ m/^\d+(\.\d+)?$/ && $doc->{$key} % $term->[0] == $term->[1];
				} elsif ($q eq '$in' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && $self->_value_in($doc->{$key}, $term);
				} elsif ($q eq '$nin' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && !$self->_value_in($doc->{$key}, $term);
				} elsif ($q eq '$size' && $term =~ m/^\d+$/) {
					return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY' && scalar @{$doc->{$key}} == $term;
				} elsif ($q eq '$all' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY';
					foreach (@$term) {
						return unless $self->_value_in($_, $doc->{$key});
					}
				} elsif ($q eq '$type' && $term =~ m/^\d+$/) {
					if ($term == 1) {
						# double
						return unless defined $doc->{$key} && $doc->{$key} =~ m/^\d+\.[1-9]\d*$/;
					} elsif ($term == 2) {
						# string
						return unless defined $doc->{$key} && $doc->{$key} =~ m/^[[:alnum:]]+$/;
					} elsif ($term == 4) {
						# array
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY';
					} elsif ($term == 8) {
						# boolean - not really supported, will always return true since everything in Perl is a boolean
					} elsif ($term == 9) {
						# date
						return unless defined $doc->{$key} && !ref $doc->{$key};
						my $date = try { DateTime::Format::W3CDTF->parse_datetime($doc->{$key}) } catch { undef };
						return unless blessed $date && $date->isa('DateTime');
					} elsif ($term == 10) {
						# null (undef)
						return unless exists $doc->{$key} && !defined $doc->{$key};
					} elsif ($term == 11) {
						# regex
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'Regexp';
					}
				}
			}
		}
	}

	return 1;
}

=head2 _array_has_eq( $value, \@array )

=cut

sub _array_has_eq {
	my ($self, $value, $array) = @_;

	foreach (@$array) {
		return 1 if $_ eq $value;
	}

	return;
}

=head2 _array_has_re( $regex, \@array )

=cut

sub _array_has_re {
	my ($self, $re, $array) = @_;

	foreach (@$array) {
		return 1 if m/$re/;
	}

	return;
}

=head2 _has_adv_que( \%hash )

=cut

sub _has_adv_que {
	my ($self, $hash) = @_;

	foreach ('$gt', '$gte', '$lt', '$lte', '$all', '$exists', '$mod', '$ne', '$in', '$nin', '$size', '$type') {
		return 1 if exists $hash->{$_};
	}

	return;
}

=head2 _value_in( $value, \@array )

=cut

sub _value_in {
	my ($self, $value, $array) = @_;

	foreach (@$array) {
		next if m/^\d+(\.\d+)?$/ && $value !~ m/^\d+(\.\d+)?$/;
		next if !m/^\d+(\.\d+)?$/ && $value =~ m/^\d+$(\.\d+)?/;
		return 1 if m/^\d+(\.\d+)?$/ && $value == $_;
		return 1 if !m/^\d+(\.\d+)?$/ && $value eq $_;
	}

	return;
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Role::DocumentMatcher

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Giddy>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Giddy>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Giddy>

=item * Search CPAN

L<http://search.cpan.org/dist/Giddy/>

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Ido Perlmuter.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
