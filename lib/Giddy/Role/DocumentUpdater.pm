package Giddy::Role::DocumentUpdater;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;

our $VERSION = "0.012_003";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::Role::DocumentUpdater - Provides document updating for Giddy::Collection

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides document updating capabilities to L<Giddy::Collection> and L<Giddy::Collection::InMemory>.

=head1 METHODS

=head2 _update_document( \%obj, \%doc )

=cut

sub _update_document {
	my ($self, $obj, $doc) = @_;

	croak "You must provide an updates hash-ref to update according to."
		unless $obj && ref $obj eq 'HASH';
	croak "You must provide a document hash-ref to update (can be empty)."
		unless defined $doc && ref $doc eq 'HASH';

	# we only need to do something if the $obj hash-ref has any advanced
	# update operations, otherwise $obj is meant to be the new $doc

	if ($self->_has_adv_upd($obj)) {
		foreach my $op (keys %$obj) {
			next if $_ eq '_name';
			if ($op eq '$inc') {
				# increase numerically
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$field} ||= 0;
					$doc->{$field} += $obj->{$op}->{$field};
				}
			} elsif ($op eq '$set') {
				# set key-value pairs
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$field} = $obj->{$op}->{$field};
				}
			} elsif ($op eq '$unset') {
				# remove key-value pairs
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					delete $doc->{$field} if $obj->{$op}->{$field};
				}
			} elsif ($op eq '$push') {
				# push values to end of arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field});
				}
			} elsif ($op eq '$pushAll') {
				# push a list of values to end of arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, @{$obj->{$op}->{$field}});
				}
			} elsif ($op eq '$addToSet') {
				# push values to arrays only if they're not already there
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field})
						unless defined $self->_index_of($obj->{$op}->{$field}, $doc->{$field});
				}
			} elsif ($op eq '$pop') {
				# pop values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					splice(@{$doc->{$field}}, $obj->{$op}->{$field}, 1);
				}
			} elsif ($op eq '$rename') {
				# rename attributes
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$obj->{$op}->{$field}} = delete $doc->{$field}
						if exists $doc->{$field};
				}
			} elsif ($op eq '$pull') {
				# remove values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					my $i = $self->_index_of($obj->{$op}->{$field}, $doc->{$field});
					while (defined $i) {
						splice(@{$doc->{$field}}, $i, 1);
						$i = $self->_index_of($obj->{$op}->{$field}, $doc->{$field});
					}
				}
			} elsif ($op eq '$pullAll') {
				# remove a list of values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					foreach my $value (@{$obj->{$op}->{$field}}) {
						my $i = $self->_index_of($value, $doc->{$field});
						while (defined $i) {
							splice(@{$doc->{$field}}, $i, 1);
							$i = $self->_index_of($value, $doc->{$field});
						}
					}
				}
			}
		}
	} else {
		# $obj is actually the new $doc
		foreach (keys %$obj) {
			next if $_ eq '_name';
			$doc->{$_} = $obj->{$_};
		}
	}
}

=head2 _has_adv_upd( \%hash )

=cut

sub _has_adv_upd {
	my ($self, $hash) = @_;

	foreach ('$inc', '$set', '$unset', '$push', '$pushAll', '$addToSet', '$pop', '$pull', '$pullAll', '$rename', '$bit') {
		return 1 if exists $hash->{$_};
	}

	return;
}

=head2 _index_of( $value, \@array )

=cut

sub _index_of {
	my ($self, $value, $array) = @_;

	for (my $i = 0; $i < scalar @$array; $i++) {
		next if $array->[$i] =~ m/^\d+(\.\d+)?$/ && $value !~ m/^\d+(\.\d+)?$/;
		next if $array->[$i] !~ m/^\d+(\.\d+)?$/ && $value =~ m/^\d+$(\.\d+)?/;
		return $i if $array->[$i] =~ m/^\d+(\.\d+)?$/ && $value == $array->[$i];
		return $i if $array->[$i] !~ m/^\d+(\.\d+)?$/ && $value eq $array->[$i];
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

	perldoc Giddy::Role::DocumentUpdater

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
