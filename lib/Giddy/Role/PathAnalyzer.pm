package Giddy::Role::PathAnalyzer;

use Any::Moose 'Role';
use namespace::autoclean;

our $VERSION = "0.012";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::Role::PathAnalyzer - Provides common path analysis methods to Giddy::Database

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides L<Giddy::Database> with common methods needed for analyzing
paths in the database.

Requires the attribute '_repo' to be implemented by consuming classes.

=head1 METHODS

=head2 _update_document( \%obj, \%doc )

=cut

requires '_repo';

sub list_contents {
	my ($self, $path) = @_;

	return sort $self->_repo->run('ls-tree', '--name-only', $path ? "HEAD:$path" : 'HEAD');
}

=head2 list_files()

Returns a list of all static files in the directory.

=cut

sub list_files {
	my ($self, $path) = @_;

	return map { $self->is_file($path.'/'.$_) } $self->list_contents($path);
}

=head2 list_dirs()

Returns a list of all child directories in the directory. These are all considered
static-file directories as well.

=cut

sub list_dirs {
	my ($self, $path) = @_;

	return map { $self->is_directory($path.'/'.$_) } $self->list_contents($path);
}

sub read_content {
	my ($self, $path) = @_;

	''.$self->_repo->run('show', "HEAD:$path");
}

sub path_exists {
	my ($self, $path) = @_;

	return -e $self->_repo->work_tree.'/'.$path ? 1 : undef;
}

sub is_file {
	my ($self, $path) = @_;

	my $t = $self->_repo->run('cat-file', '-t', "HEAD:$path");
	return $t eq 'blob' ? 1 : undef;
}

sub is_directory {
	my ($self, $path) = @_;

	my $t = $self->_repo->run('cat-file', '-t', "HEAD:$path");
	return $t eq 'tree' ? 1 : undef;
}

sub is_document_dir {
	my ($self, $path) = @_;

	return $self->path_exists($path.'/'.'attributes.yaml');
}

sub is_static_dir {
	my ($self, $path) = @_;

	# a static dir is marked by a .static file, but it doesn't have to have
	# that file if it's a child of a static dir
	while ($path) {
		return 1 if $self->path_exists($path.'/.static');
		$path = $self->up($path);
	}

	return;
}

sub up {
	my ($self, $path) = @_;

	if ($path =~ m!/[^/]+$!) {
		return $`;
	} else {
		return '';
	}
}

1;
