package Giddy::Collection::InMemory;

# ABSTRACT: An in-memory collection (result of queries).

use Any::Moose;
use namespace::autoclean;

our $VERSION = "0.012";
$VERSION = eval $VERSION;

extends 'Giddy::Collection';

=head1 NAME

Giddy::Collection::InMemory - An in-memory collection (result of queries).

=head1 SYNOPSIS

	my $in_memory_collection = $collection->find({ _name => qr/wow/ });

	# use $in_memory_collection just like any other Giddy::Collection object

=head1 DESCRIPTION

This class represents in-memory collections. These are created by running C<find()>
and C<grep()> queries on other collection (either real collections represented by
L<Giddy::Collection> or other in-memory collections).

Except from not being able to drop in-memory collections, using them is performed
I<exactly> the same as using real ones, so refer to L<Giddy::Collection> for details.

=head1 EXTENDS

L<Giddy::Collection>

=head1 ATTRIBUTES

=head2 _documents

An array-reference of the documents in the collection. Not to be used externally.

=head2 _loaded

A hash-ref containing loaded document structures. Not tobe used externally.

=head2 _query

A hash-ref with details about the query that created the collection.
Not to be used externally.

=cut

has '_documents' => (is => 'ro', isa => 'Tie::IxHash', default => sub { Tie::IxHash->new }, writer => '_set_documents');

has '_loaded' => (is => 'ro', isa => 'HashRef[HashRef]', default => sub { {} }, writer => '_set_loaded');

has '_query' => (is => 'ro', isa => 'HashRef', required => 1);

=head1 METHODS

Just the same as in L<Giddy::Collection>, of course, except for:

=head2 drop()

Doesn't do anything. Really.

=cut

sub drop { 1 }

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
