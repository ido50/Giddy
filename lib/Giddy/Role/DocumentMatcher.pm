package Giddy::Role::DocumentMatcher;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use Data::Compare;
use DateTime::Format::W3CDTF;
use Path::Abstract qw/--no_0_093_warning/;
use Try::Tiny;

=head1 NAME

Giddy::Role::DocumentMatcher - Provides query parsing and document matching for Giddy::Collection

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides document matching capabilities to L<Giddy::Collection> and L<Giddy::Collection::InMemory>.

=head1 METHODS

=head2 _match_by_name( $name, \%options )

=cut

sub _match_by_name {
	my ($self, $name, $opts) = @_;

	$name ||= '';
	$opts ||= {};

	# return all documents if we don't really have a query
	$name eq '' && return $self->_documents;

	my $docs = Tie::IxHash->new;
	foreach ($self->_documents->Keys) {
		my $t = $self->_documents->FETCH($_);
		my $doc_path = Path::Abstract->new($_);
		my $doc_name = $doc_path->last;
		$docs->STORE($_ => $t)
			if $self->_attribute_matches({ _name => $doc_name }, '_name', $name);
	}

	$docs->SortByKey;

	return $docs;
}

=head2 _match_by_query( [ \%query, \%options ] )

=cut

sub _match_by_query {
	my ($self, $query, $opts) = @_;

	$query ||= {};
	$opts ||= {};

	# return all documents if we don't really have a query
	scalar keys %$query == 0 && $self->_documents;

	my $docs = Tie::IxHash->new;
	my $loaded = {};
	my $i = 0;
	foreach ($self->_documents->Keys) {
		my $doc = $self->_load_document($i++);
		if ($self->_document_matches($doc, $query)) {
			$docs->STORE($_ => $self->_documents->FETCH($_));
			$loaded->{$_} = $doc;
		}
	}

	return ($docs, $loaded);
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
				} elsif ($q eq '$eq') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if ($doc->{$key} =~ m/^\d+(\.\d+)?$/) {
						return unless $doc->{$key} == $term;
					} else {
						return unless $doc->{$key} eq $term;
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
				} elsif ($q eq '$type' && !ref $term) {
					if ($term eq 'int') {
						return unless defined $doc->{$key} && $doc->{$key} =~ m/^\d+$/;
					} elsif ($term eq 'double') {
						return unless defined $doc->{$key} && $doc->{$key} =~ m/^\d+\.[1-9]\d*$/;
					} elsif ($term eq 'string') {
						return unless defined $doc->{$key} && $doc->{$key} =~ m/^[[:alnum:]]+$/;
					} elsif ($term eq 'array') {
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY';
					} elsif ($term eq 'bool') {
						# boolean - not really supported, will always return true since everything in Perl is a boolean
					} elsif ($term eq 'date') {
						return unless defined $doc->{$key} && !ref $doc->{$key};
						my $date = try { DateTime::Format::W3CDTF->parse_datetime($doc->{$key}) } catch { undef };
						return unless blessed $date && $date->isa('DateTime');
					} elsif ($term eq 'null') {
						return unless exists $doc->{$key} && !defined $doc->{$key};
					} elsif ($term eq 'regex') {
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
