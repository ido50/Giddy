package Giddy::Role::DocumentUpdater;

use Any::Moose 'Role';
use namespace::autoclean;
use Data::Compare;
use DateTime::Format::W3CDTF;
use Try::Tiny;
use Carp;

=head1 NAME

Giddy::Role::DocumentUpdater - Provides document updating for Giddy::Collection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut

sub _update_document {
	my ($self, $obj, $doc) = @_;

	croak "You must provide an updates hash-ref to update according to."
		unless $obj && ref $obj eq 'HASH';

	# $doc can be empty, but must be a hash-ref
	$doc ||= {};
	croak "Document to update must be a hash-ref."
		unless ref $doc eq 'HASH';

	# we only need to do something if the $obj hash-ref has any advanced
	# update operations, otherwise $obj is meant to be the new $doc

	if ($self->_has_adv_upd($obj)) {
		foreach my $op (keys %$obj) {
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
					croak "The $field attribute is not an array in $doc->{_path}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field});
				}
			} elsif ($op eq '$pushAll') {
				# push a list of values to end of arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_path}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, @{$obj->{$op}->{$field}});
				}
			} elsif ($op eq '$addToSet') {
				# push values to arrays only if they're not already there
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_path}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field})
						unless defined $self->_index_of($obj->{$op}->{$field}, $doc->{$field});
				}
			} elsif ($op eq '$pop') {
				# pop values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_path}."
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
					croak "The $field attribute is not an array in $doc->{_path}."
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
					croak "The $field attribute is not an array in $doc->{_path}."
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
		return $obj;
	}

	return $doc;
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
		return $i if $array->[$i] =~ m/^\d+(\.\d+)?$/ && $value == $_;
		return $i if $array->[$i] !~ m/^\d+(\.\d+)?$/ && $value eq $_;
	}

	return;
}

1;
