package Giddy::StaticDirectory;

# ABSTRACT: A Giddy directory of static files.

use Any::Moose;
use namespace::autoclean;

use Carp;
use File::Spec;

=head1 NAME

Giddy::StaticDirectory - A Giddy directory of static files.

=head1 SYNOPSIS

	my $dir = $coll->get_static_dir('pictures');

=head1 DESCRIPTION

This class represents Giddy static-file directories, which are directories that
contain files which aren't documents and do not change often, most probably
binary files (pictures, videos, songs) and other files which are often called
"static" in the world of websites. Any sub-directory in a static directory is
also considered a static directory, and they are infinitely nestable.

=head1 ATTRIBUTES

=head2 path

The relative path of the directory. Always has a starting slash. Required.

=head2 _collection

The L<Giddy::Collection> object the directory belongs to. This is even if the
directory is not a direct child of the collection, but some descendant of it.
Required.

=cut

has 'path' => (is => 'ro', isa => 'Str', required => 1);

has '_collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

=head1 OBJECT METHODS

=head2 list_files()

Returns a list of all static files in the directory.

=cut

sub list_files {
	my $self = shift;

	my @files;
	foreach ($self->_collection->_database->_repo->run('ls-tree', '--name-only', 'HEAD:'.$self->_spath)) {
		my $t = $self->_database->_repo->run('cat-file', '-t', 'HEAD:'.File::Spec->catfile($self->_spath, $_));
		if ($t eq 'blob') {
			push(@files, $t);
		}
	}

	return @files;
}

=head2 list_dirs()

Returns a list of all child directories in the directory. These are all considered
static-file directories as well.

=cut

sub list_dirs {
	my $self = shift;

	my @dirs;
	foreach ($self->_collection->_database->_repo->run('ls-tree', '--name-only', 'HEAD:'.$self->_spath)) {
		my $t = $self->_database->_repo->run('cat-file', '-t', 'HEAD:'.File::Spec->catfile($self->_spath, $_));
		if ($t eq 'tree') {
			push(@dirs, $t);
		}
	}

	return @dirs;
}

=head3 get_static_dir( $name )

Returns a Giddy::StaticDirectory object for a child directory of the current
directory named C<$name>. If the directory does not exist, it will be created.
If a file named C<$name> exists in the directory, this method will croak.

=cut

sub get_static_dir {
	my ($self, $name) = @_;

	croak "You must provide the name of the static directory to load."
		unless $name;

	# try to find such a directory
	if (grep {$_ eq $name} $self->_database->_repo->run('ls-tree', '--name-only', 'HEAD:'.$self->_spath)) {
		my $t = $self->_collection->_database->_repo->run('cat-file', '-t', 'HEAD:'.File::Spec->catdir($self->_spath, $name));
		if ($t eq 'tree') {
			return Giddy::StaticDirectory->new(path => File::Spec->catdir($self->path, $name), _collection => $self);
		} elsif ($t eq 'blob') {
			croak "A file named $name exists in the directory, there cannot be a directory named like that as well.";
		}
	}

	# okay, let's create the directory
	make_path(File::Spec->catdir($self->_repo->work_tree, $self->_spath, $name), { mode => 0775 });
	$self->mark(File::Spec->catdir($self->path, $name));

	return Giddy::StaticDirectory->new(path => File::Spec->catdir($self->path, $name), _collection => $self);
}

=head1 INTERNAL METHODS

The following methods are only to be used internally.

=head2 _spath()

=cut

sub _spath {
	($_[0]->path =~ m!^/(.+)$!)[0];
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::StaticDirectory

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
