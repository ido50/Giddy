package Giddy;

# ABSTRACT: Schema-less, versioned media/document database based on Git.

use Any::Moose;
use namespace::autoclean;

use Carp;
use Git::Repository 1.18;
use Giddy::Database;

our $VERSION = "0.012_005";
$VERSION = eval $VERSION;

=head1 NAME

Giddy - Schema-less, versioned media/document database based on Git.

=head1 SYNOPSIS

	use Giddy;

	my $giddy = Giddy->new;

	my $db = $giddy->get_database('/path/to/database');

=head1 DESCRIPTION

WARNING: THIS IS ALPHA SOFTWARE, RELEASED FOR TESTING PURPOSES ONLY. DO
NOT USE IT ON A PRODUCTION ENVIRONMENT YET. IT'S INCOMPLETE, BUG-RIDDEN, LIKELY
TO CHANGE, AND WILL RUN OVER YOUR CAT.

Giddy is a schema-less (as in NoSQL), versioned database system for Unix-like
operating systems, built on top of Git. A database in Giddy is simply a Git
repository, providing the database with automatic, comprehensive versioning and
distributive capabilities.

As opposed to most modern database systems, Giddy aims to be human editable.
One can create/edit/delete database entries with nothing but a text editor
and some simple git commands (YAML has been chosen as the serialization
format since YAML is well suited as a human editable format; however, JSON
support is planned). This module provides an API for usage by Perl applications.

Main database features (not all features implemented yet):

=over

=item * Human editable

=item * Multiple version concurrency

=item * Concurrent transactions 

=item * Distributed peers

=item * Disconnected operation

=item * Consistent UTF-8 encoding

=item * Other fancy words

=back

STOP: This document (and all other module documentation provided with the
distribution) are for reference purposes only. Please read L<Giddy::Manual>
before using Giddy to learn about the database system and how to use it.

=head1 CLASS METHODS

=head2 new()

Creates a new instance of this module.

=head1 OBJECT METHODS

=head2 get_database( $path )

Returns a L<Giddy::Database> object tied to a Git repository located on the file
system. Please provide full path names to prevent potential problems.

If the path doesn't exist, Giddy will attempt to create it and initialize it
as a Git repository. It will also create an empty file called ".giddy" inside
the database and perform an initial commit. You can safely remove that file
after that.

=cut

sub get_database {
	my ($self, $path) = @_;

	# remove trailing slash, if exists
	$path =~ s!/$!! if $path;

	croak "You must provide the path to the Giddy database."
		unless $path;

	# is this an existing database or a new one?
	if (-d $path && -d "${path}/.git") {
		# existing
		return Giddy::Database->new(_repo => Git::Repository->new(work_tree => $path));
	} else {
		# new one, let's create the repository's directory
		Git::Repository->run('init', $path)
			|| croak "Failed creating new Giddy repository, please check provided path is valid and that you have appropriate permissions to create the repository.";
		my $db = Giddy::Database->new(_repo => Git::Repository->new(work_tree => $path));
		
		# create an empty .giddy file, stage it and commit, so our database will be "live"
		$db->_touch('.giddy');
		$db->stage('.giddy');
		$db->commit('initial commit');

		return $db;
	}
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy

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
