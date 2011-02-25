package Giddy;

# ABSTRACT: Schemaless, versioned document database based on Git.

use Any::Moose;
use namespace::autoclean;

use File::Spec;
use File::Util;
use Giddy::Database;
use Carp;

=head1 NAME

Giddy - Schemaless, versioned media/document database based on Git.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 _futil

A L<File::Util> object to be used by the module. Automatically created.

=cut

has '_futil' => (is => 'ro', isa => 'File::Util', default => sub { File::Util->new });

=head1 CLASS METHODS

=head2 new()

=head1 OBJECT METHODS

=head2 get_database( $path )

=cut

sub get_database {
	my ($self, $path) = @_;

	# remove trailing slash, if exists
	$path =~ s!/$!! if $path;

	croak "You must provide the path to the Giddy database."
		unless $path;

	# is this an existing database or a new one?
	if (-d $path && -d File::Spec->catdir($path, '.git')) {
		# existing
		return Giddy::Database->new(_repo => Git::Repository->new(work_tree => $path), _futil => $self->_futil);
	} else {
		# new one
		return Giddy::Database->new(_repo => Git::Repository->create(init => $path), _futil => $self->_futil);
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

Copyright 2010 Ido Perlmuter.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

__PACKAGE__->meta->make_immutable;
