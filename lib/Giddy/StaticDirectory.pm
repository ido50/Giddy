package Giddy::StaticDirectory;

# ABSTRACT: A Giddy directory of static files.

use Any::Moose;
use namespace::autoclean;

use Carp;
use IO::File;

our $VERSION = "0.012_003";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::StaticDirectory - A Giddy directory of static files.

=head1 SYNOPSIS

	my $dir = $coll->get_static_dir('static_files');

	my $fh = $dir->open_text_file("robots.txt");
	$fh->print("User-agent: *\nDisallow:");
	$fh->close;

	$db->stage('static_files');
	$db->commit('create a static-file directory');

=head1 DESCRIPTION

This class represents Giddy static-file directories, which are directories that
contain files which aren't documents and do not change often, most probably
binary files (pictures, videos, songs) and other files which are often called
"static" in the world of websites. Any sub-directory in a static directory is
also considered a static directory, with infinite nestability.

=head1 ATTRIBUTES

=head2 path

The relative path of the directory. Always has a starting slash. Required.

=head2 coll

The L<Giddy::Collection> object the directory belongs to. This is even if the
directory is not a direct child of the collection, but some descendant of it.
Required.

=cut

has 'path' => (is => 'ro', isa => 'Str', required => 1);

has 'coll' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

=head1 OBJECT METHODS

=head2 list_files()

Returns a list of all static files in the directory.

=cut

sub list_files {
	my $self = shift;

	return $self->coll->db->_list_files($self->path);
}

=head2 list_dirs()

Returns a list of all child directories in the directory. These are all considered
static-file directories as well.

=cut

sub list_dirs {
	my $self = shift;

	return $self->coll->db->_list_dirs($self->path);
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

	my $fpath = $self->path.'/'.$name;

	# try to find such a directory
	if ($self->coll->db->_path_exists($fpath)) {
		if ($self->coll->db->_is_directory($fpath)) {
			# we don't check if the directory is a static directory, since by
			# definition a descendant of a static directory is a static directory
			return Giddy::StaticDirectory->new(path => $fpath, _collection => $self);
		} else {
			croak "A file named $name exists in the ".$self->path." static directory, there cannot be a directory named like that as well.";
		}
	} else {
		# okay, let's create the directory
		$self->coll->db->_create_dir($fpath);
		$self->coll->db->stage($fpath);

		return Giddy::StaticDirectory->new(path => $fpath, _collection => $self);
	}
}

=head2 open_text_file( $name, [ $mode ] )

Creates a new file named C<$name> (if not exists) inside the static directory,
opens it and returns a L<IO::File> object handle. If C<$mode> is not provided,
C<< '>:utf8' >> is used (meaning the file is truncated (if exists) and opened
for writing with automatic UTF-8 encoding of written data). You can provide other
modes if you wish, but keep in mind that Giddy expects all your files to be UTF-8.

=cut

sub open_text_file {
	my ($self, $name, $mode) = @_;

	croak "You must provide the name of the text file to open."
		unless $name;

	$mode ||= '>:utf8';

	my $fpath = $self->coll->db->_repo->work_tree.'/'.$self->path.'/'.$name;

	IO::File->new($fpath, $mode) || croak "Can't open text file $name: $!";
}

=head2 open_binary_file( $name, [ $mode, $layer ] )

Creates a new file named C<$name> (if not exists) inside the static directory,
opens it, C<binmode>s it and returns a L<IO::File> object handle. If C<$mode>
isn't provided, C<< '>' >> is used (meaning the file is truncated (if exists)
and opened for writing). If your provide a layer string is provided, it will be
passed to C<binmode()> when calling it.

=cut

sub open_binary_file {
	my ($self, $name, $mode, $layer) = @_;

	croak "You must provide the name of the binary file to open."
		unless $name;

	$mode ||= '>';

	my $fpath = $self->coll->db->_repo->work_tree.'/'.$self->path.'/'.$name;

	my $fh = IO::File->new($fpath, $mode) || croak "Can't open binary file $name: $!";
	$fh->binmode($layer);
	return $fh;
}

=head2 read_file( $name )

Returns the contents of the file named C<$name> in the static directory. Assumes
the file exists and has been indexed, will croak if not.

=cut

sub read_file {
	my ($self, $name) = @_;

	croak "You must provide the name of the file to read."
		unless $name;

	return $self->coll->db->_read_content($self->path.'/'.$name);
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
