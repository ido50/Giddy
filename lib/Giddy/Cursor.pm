package Giddy::Cursor;

# ABSTRACT: A cursor/iterator for Giddy query results.

use Any::Moose;
use namespace::autoclean;

=head1 NAME

Giddy::Cursor - A cursor/iterator for Giddy query results.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 count

An integer representing the number of results found by the query. Can be
used externally.

=head2 _results

An array-reference of the results (before loading) found by the query.
Not to be used externally.

=head2 _query

A hash-ref with details about the query performed. Not to be used externally.

=head2 _loc

An integer representing the current location of the iterator in the results array.
Not to be used externally.

=cut

has 'count' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_count');

has '_results' => (is => 'ro', isa => 'ArrayRef[HashRef]', writer => '_set_results', predicate => '_has_results');

has '_query' => (is => 'ro', isa => 'HashRef', required => 1);

has '_loc' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_loc');

has '_loaded' => (is => 'ro', isa => 'HashRef[HashRef]', default => sub { {} }, writer => '_set_loaded');

=head1 OBJECT METHODS

=head2 all()

Returns an array of all the documents/articles found by the query.

=cut

sub all {
	my $self = shift;
	my @results;
	while ($self->has_next) {
		push(@results, $self->next);
	}
	return @results;
}

=head2 has_next()

Returns a true value if the iterator hasn't reached the end of the results
array yet (and thus C<next()> can be called).

=cut

sub has_next {
	$_[0]->_loc < $_[0]->count;
}

=head2 next()

Returns the document/article found by the query from the iterator's current
position, and increases it to point to the next result.

=cut

sub next {
	my $self = shift;

	return unless $self->has_next;

	my $next = $self->_load_result($self->_results->[$self->_loc]);
	$self->_inc_loc;
	return $next;
}

=head2 rewind()

Resets to iterator to point to the first result.

=cut

sub rewind {
	$_[0]->_set_loc(0);
}

=head2 first()

Returns the first result found by the query (or C<undef> if none found),
regardless of the iterator's current position (which will not change).

=cut

sub first {
	my $self = shift;

	return unless $self->count;

	return $self->_load_result($self->_results->[0]);
}

=head2 last()

Returns the last result found by the query (or C<undef> if none found),
regardless of the iterator's current position (which will not change).

=cut

sub last {
	my $self = shift;

	return unless $self->count;

	return $self->_load_result($self->_results->[$self->count - 1]);
}

=head1 INTERNAL METHODS

=head2 _add_result( \%res )

Appends a result hash-ref to the cursor.

=cut

sub _add_result {
	my ($self, $res) = @_;

	my @results = @{$self->_results || []};
	push(@results, $res);
	$self->_set_results(\@results);
	$self->_inc_count;
}

=head2 _inc_count()

Increases the cursor's counter by one.

=cut

sub _inc_count {
	my $self = shift;

	$self->_set_count($self->count + 1);
}

=head2 _inc_loc()

Increases the iterator's position by one.

=cut

sub _inc_loc {
	my $self = shift;

	$self->_set_loc($self->_loc + 1);
}

=head2 _load_result( \%res )

Loads a document/article from a result hash-ref.

=cut

sub _load_result {
	my ($self, $result) = @_;

	if ($result->{document_file}) {
		if (exists $self->_loaded->{$result->{document_file}}) {
			return $self->_loaded->{$result->{document_file}};
		} else {
			my $doc = $self->_query->{coll}->_load_document_file($result->{document_file}, $self->_query->{opts}->{working});
			$self->_add_loaded($result->{document_file}, $doc);
			return $doc;
		}
	} elsif ($result->{document_dir}) {
		if (exists $self->_loaded->{$result->{document_dir}}) {
			return $self->_loaded->{$result->{document_dir}};
		} else {
			my $doc = $self->_query->{coll}->_load_document_dir($result->{document_dir}, $self->_query->{opts}->{working}, $self->_query->{opts}->{skip_binary});
			$self->_add_loaded($result->{document_dir}, $doc);
			return $doc;
		}
	}
}

=head2 _add_loaded( $path, \%doc )

Adds the loaded document to the cursor

=cut

sub _add_loaded {
	my ($self, $path, $doc) = @_;

	$self->_loaded->{$path} = $doc;
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Cursor

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

__PACKAGE__->meta->make_immutable;
