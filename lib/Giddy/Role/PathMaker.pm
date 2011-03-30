package Giddy::Role::PathMaker;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use File::Path qw/make_path/;

our $VERSION = "0.012_001";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::Role::PathMaker - Provides file and directory creation for Giddy::Database

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides L<Giddy::Database> with common methods needed for creating
paths in the database.

Requires the attribute '_repo' to be implemented by consuming classes.

=cut

requires '_repo';

=head1 METHODS

=head2 _create_dir( $path )

Creates a directory under C<$path> and chmods it 0775. If path already exists,
nothing will happen.

=cut

sub _create_dir {
	my ($self, $path) = @_;

	make_path($self->_repo->work_tree.'/'.$path, { mode => 0775 });
}

=head2 _mark_dir_as_static( $path )

Marks a path (assumed to be a directory) as a static-file directory by creating
an empty '.static' file under it.

=cut

sub _mark_dir_as_static {
	my ($self, $path) = @_;

	$self->_touch($path.'/.static');
}

=head2 _touch( $path )

Creates an empty file in C<$path> and chmods it 0664.

=cut

sub _touch {
	my ($self, $path) = @_;

	open(FILE, ">:utf8", $self->_repo->work_tree.'/'.$path)
		|| croak "Can't _touch $path: $!";
	close FILE;
	chmod(0664, $self->_repo->work_tree.'/'.$path);
}

=head2 _create_file( $path, $content, $mode )

Creates a file called C<$path>, with the provided content, and chmods it to
C<$mode>.

=cut

sub _create_file {
	my ($self, $path, $content, $mode) = @_;

	# there's no need to open the output file in binary :utf-8 mode,
	# as the YAML Dump() function returns UTF-8 encoded data (so it seems)

	open(FILE, '>', $self->_repo->work_tree.'/'.$path)
		|| croak "Can't open file $path for writing: $!";
	flock(FILE, 2);
	print FILE $content;
	close(FILE)
		|| carp "Error closing file $path: $!";
	chmod($mode, $self->_repo->work_tree.'/'.$path);
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Role::PathMaker

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
