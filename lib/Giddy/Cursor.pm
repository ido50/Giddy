package Giddy::Cursor;

use Any::Moose;
use Carp;

has 'query' => (is => 'ro', isa => 'HashRef', required => 1);

has 'count' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_count');

has 'results' => (is => 'ro', isa => 'ArrayRef', writer => '_set_results', predicate => 'has_results');

sub _add_result {
	my ($self, $res) = @_;

	my @results = @{$self->results || []};
	push(@results, $res);
	$self->_set_results(\@results);
	$self->_inc_count;
}

sub _inc_count {
	my $self = shift;

	$self->_set_count($self->count + 1);
}

sub all {
	@{shift->results || []};
}

sub first {
	my $self = shift;

	return unless $self->count;

	return $self->results->[0];
}

sub last {
	my $self = shift;

	return unless $self->count;

	return $self->results->[$self->count - 1];
}

__PACKAGE__->meta->make_immutable;
