package Giddy::Role::PathMaker;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use File::Path qw/make_path/;

our $VERSION = "0.012";
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

=cut

sub create_dir {
	my ($self, $path) = @_;

	make_path($self->_repo->work_tree.'/'.$path, { mode => 0775 });
}

sub mark_dir_as_static {
	my ($self, $path) = @_;

	$self->touch($path.'/.static');
}

sub touch {
	my ($self, $path) = @_;

	open(FILE, ">:utf8", $self->_repo->work_tree.'/'.$path)
		|| croak "Can't touch $path: $!";
	close FILE;
	chmod(0664, $self->_repo->work_tree.'/'.$path);
}

=head2 create_file( $fpath, $content, $mode )

=cut

sub create_file {
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

1;
