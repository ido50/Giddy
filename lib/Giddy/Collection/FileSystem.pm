package Giddy::Collection::FileSystem;

# ABSTRACT: A real collection stored in the file system.

our $VERSION = "0.020";
$VERSION = eval $VERSION;

use Moose;
use namespace::autoclean;

use Carp;

with 'Giddy::Collection';

=head1 NAME

Giddy::Collection::FileSystem - A real collection stored in the file system.

=head1 SYNOPSIS

	my $coll = $db->get_collection('path/to/collection');

=head1 DESCRIPTION

This class represents file system collections. These are real collections
residing in the database repository. The main API of both file system
collections and in-memory collections (see L<Giddy::Collection::InMemory>)
is actually provided by the L<Moose role|Moose::Role> L<Giddy::Collection>.

=head1 CONSUMES

L<Giddy::Collection>

=head1 ATTRIBUTES

I<None other than those provided by Giddy::Collection>.

=head1 OBJECT METHODS

=head2 drop()

Removes the collection from the database. Will not work (and croak) on
the root collection. Every document and sub-collection in the collection will
be removed. This method is not available on L<Giddy::Collection::InMemory> objects.

=cut

sub drop {
	my $self = shift;

	croak "You cannot drop the root collection."
		if $self->path eq '';

	$self->db->_repo->run('rm', '-r', '-f', $self->path);
}

=head1 INTERNAL METHOSD

=head2 _documents()

Returns a sorted L<Tie::IxHash> object of all documents in the collection.

=cut

sub _documents {
	my $self = shift;

	my $docs = Tie::IxHash->new;
	foreach ($self->db->_list_contents($self->path)) {
		my $full_path = $self->_path_to($_);

		# we're only looking for document directories and document files
		if ($self->db->_is_document_dir($full_path)) {
			$docs->STORE($_ => 'dir');
		} elsif ($self->db->_is_file($full_path)) {
			$docs->STORE($_ => 'file');
		}
	}

	return $docs;
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Collection::FileSystem

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
