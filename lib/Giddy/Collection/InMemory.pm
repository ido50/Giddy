package Giddy::Collection::InMemory;

# ABSTRACT: An in-memory collection (result of queries).

use Any::Moose;
use namespace::autoclean;

extends 'Giddy::Collection';

=head1 NAME

Giddy::Collection::InMemory - An in-memory collection (result of queries).

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 EXTENDS

L<Giddy::Collection>

=head1 ATTRIBUTES

=head2 _documents

An array-reference of the documents in the collection. Not to be used externally.

=head2 _query

A hash-ref with details about the query that created the collection.
Not to be used externally.

=cut

has '_documents' => (is => 'ro', isa => 'ArrayRef[HashRef]', default => sub { [] }, writer => '_set_documents_ref');

has '_loaded' => (is => 'ro', isa => 'HashRef[HashRef]', default => sub { {} }, writer => '_set_loaded');

has '_query' => (is => 'ro', isa => 'HashRef', required => 1);

=head1 METHODS

=head2 count()

Returns the number of documents found by the query and thus residing in
this in-memory collection.

=cut

sub count {
	my $self = shift;
	my $docs = $self->_documents;
	return scalar @$docs;
}

=head1 INTERNAL METHODS

The following methods are only to be used internally.

=head2 _set_documents( @docs )

=cut

sub _set_documents {
	my ($self, $matched) = @_;

	my $docs = [];
	my $loaded = {};
	foreach (@$matched) {
		if (ref $_ eq 'ARRAY') {
			my $path = $_->[0]->{document_file} || $_->[0]->{document_dir};
			push(@$docs, $_->[0]);
			$loaded->{$path} = $_->[1] if $_->[1];
		} else {
			push(@$docs, $_);
		}
	}

	$self->_set_documents_ref($docs);
	$self->_set_loaded($loaded);
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Collection::InMemory

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
