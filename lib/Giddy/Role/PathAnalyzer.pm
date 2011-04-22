package Giddy::Role::PathAnalyzer;

use Any::Moose 'Role';
use namespace::autoclean;

our $VERSION = "0.013_001";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::Role::PathAnalyzer - Provides common path analysis methods to Giddy::Database

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides L<Giddy::Database> with common methods needed for analyzing
paths in the database.

Requires the attribute '_repo' to be implemented by consuming classes.

=cut

requires '_repo';

=head1 METHODS

=head2 _list_contents( $path )

Returns a list of all files and directories in C<$path>. Assumes C<$path> is a directory.

=cut

sub _list_contents {
	my ($self, $path) = @_;

	return grep { $_ ne '.giddy' } sort $self->_repo->run('ls-tree', '--name-only', $path ? "HEAD:$path" : 'HEAD');
}

=head2 _list_files( $path )

Returns a list of all static files in the directory. Assumes C<$path> is a directory.

=cut

sub _list_files {
	my ($self, $path) = @_;

	return grep { $self->_is_file($path.'/'.$_) } $self->_list_contents($path);
}

=head2 _list_dirs( $path )

Returns a list of all child directories in the directory. Assumes C<$path> is a directory.

=cut

sub _list_dirs {
	my ($self, $path) = @_;

	return grep { $self->_is_directory($path.'/'.$_) } $self->_list_contents($path);
}

=head2 _read_content( $path )

Returns the contents of the file stored in C<$path>.

=cut

sub _read_content {
	my ($self, $path) = @_;

	''.$self->_repo->run('show', "HEAD:$path");
}

=head2 _path_exists( $path )

Returns true if C<$path> exists in the database index (i.e. it's not enough for
the path to exist in the working directory, it must be in the Git index as well).

=cut

sub _path_exists {
	my ($self, $path) = @_;

	my ($dir, $name) = ('', '');
	if ($path && $path =~ m!/([^/]+)$!) {
		$name = $1;
		$dir = $`;
	} else {
		$name = $path;
	}

	if (grep { $_ eq $name } $self->_list_contents($dir)) {
		return 1;
	}

	return;
}

=head2 _is_file( $path )

Returns true if C<$path> is a file. Assumes path exists.

=cut

sub _is_file {
	my ($self, $path) = @_;

	my $t = $self->_repo->run('cat-file', '-t', "HEAD:$path");
	return $t eq 'blob' ? 1 : undef;
}

=head2 _is_directory( $path )

Returns true if C<$path> is a directory. Assumes path exists.

=cut

sub _is_directory {
	my ($self, $path) = @_;

	my $t = $self->_repo->run('cat-file', '-t', "HEAD:$path");
	return $t eq 'tree' ? 1 : undef;
}

=head2 _is_document_dir( $path )

Returns true if C<$path> is a document directory. Assumes path exists.

=cut

sub _is_document_dir {
	my ($self, $path) = @_;

	return $self->_path_exists($path.'/'.'attributes.yaml');
}

=head2 _is_static_dir( $path )

Returns true if C<$path> is a static-file directory. Assumes path exists.

=cut

sub _is_static_dir {
	my ($self, $path) = @_;

	# a static dir is marked by a .static file, but it doesn't have to have
	# that file if it's a child of a static dir
	while ($path) {
		return 1 if $self->_path_exists($path.'/.static');
		$path = $self->_up($path);
	}

	return;
}

=head2 _up( $path )

Returns the parent directory of C<$path> (if any).

=cut

sub _up {
	my ($self, $path) = @_;

	if ($path =~ m!/[^/]+$!) {
		return $`;
	} else {
		return '';
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

	perldoc Giddy::Role::PathAnalyzer

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
