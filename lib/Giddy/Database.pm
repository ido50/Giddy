package Giddy::Database;

# ABSTRACT: A Giddy database.

our $VERSION = "0.020";
$VERSION = eval $VERSION;

use Moose;
use namespace::autoclean;

use Carp;
use File::Path qw/make_path/;
use Git::Repository::Log::Iterator;

=head1 NAME

Giddy::Database - A Giddy database.

=head1 SYNOPSIS

	my $db = $giddy->get_database('/path/to/database');

=head1 DESCRIPTION

This class represents Giddy databases. Aside from providing you with the ability
to create and get collections from the database, it provides methods which are
global to the database, like commit changes, undoing changes, etc.

=head1 ATTRIBUTES

=head2 _repo

A L<Git::Repository> object, tied to the git repository of the Giddy database.
This is a required attribute. Not meant to be used externally, but knock yourself
out if you feel the need to run specific Git commands.

=head2 _staged

A list of paths staged (added) to the next commit job. Internally maintained.

=cut

has '_repo' => (is => 'ro', isa => 'Git::Repository', required => 1);

has '_staged' => (is => 'ro', isa => 'ArrayRef[Str]', default => sub { [] }, writer => '_set_staged');

=head1 OBJECT METHODS

=head2 get_collection( [ $path_to_coll ] )

Returns a L<Giddy::Collection::FileSystem> object tied to a certain directory in the database.
If a path is not provided, the root collection ('') will be used. If the collection
does not exist, Giddy will attempt to create it. The path provided has to be relative
to the database's full path, with no starting slash.

=cut

sub get_collection {
	my ($self, $path) = @_;

	$path ||= '';

	if ($path) {
		croak "Path of collection to get must not start with a slash."
			if $path =~ m!^/!;

		croak "The collection path exists in the database but is not a collection."
			if $self->_path_exists($path) && !$self->_is_collection($path);

		# create the collection directory (unless it already exists)
		$self->_create_dir($path);
	}

	return Giddy::Collection::FileSystem->new(db => $self, path => $path);
}

=head2 commit( [$commit_msg] )

Commits all pending changes with a commit message. If not provided, Giddy will
use a default commit message listing the number of changes performed.

=cut

sub commit {
	my ($self, $msg) = @_;

	$msg ||= "Commited ".scalar(@{$self->_staged})." changes";

	# commit
	$self->_repo->run('commit', '-m', $msg);

	# clear marked list
	$self->_set_staged([]);

	return 1;
}

=head2 stage( @paths )

Marks files/directories as to be staged. Mostly called automatically by
C<new_collection()>, C<new_document()>, etc., but you can use it if you need to.
Paths are relative to database's path and should not contain starting slashes.

=cut

sub stage {
	my ($self, @paths) = @_;

	croak "You must provide the relative path of the file/directory to stage."
		unless scalar @paths;

	foreach (@paths) {
		# stage the file
		$self->_repo->run('add', $_);
	}

	# store files in object
	my $staged = $self->_staged;
	push(@$staged, @paths);
	$self->_set_staged($staged);
}

=head2 find( [ $path, [\%options] ] )

Searches the Giddy repository for documents that match the provided
path. The path has to be relative to the repository's root directory, which
is considered the empty string. This string will be used if C<$path> is not provided. This is
a convenience method for finding documents by path. See L<Giddy::Collection> and
L<Giddy::Manual/"FULL PATH FINDING"> for more information.

=cut

sub find {
	my ($self, $path, $opts) = @_;

	croak "find() expected a hash-ref of options, but received ".ref($opts)
		if $opts && (!ref $opts || ref $opts ne 'HASH');

	$opts ||= {};

	# in which directory are we searching?
	my ($dir, $name) = ('', '');
	if ($path && $path =~ m!/([^/]+)$!) {
		$name = $1;
		$dir = $`;
	} else {
		$name = $path;
	}

	return $self->get_collection($dir)->find($name, $opts);
}

=head2 find_one( [ $path, \%options ] )

Same as calling C<< find($path, $options)->first() >>.

=cut

sub find_one {
	shift->find(@_)->first;
}

=head2 undo( [ $num ] )

=head2 undo( $commit_checksum )

Cancels the C<$num>th latest commit performed (if $num is 0 or not passed, the
latest commit is cancelled). Any changes performed by the commit cancelled
are forever lost. If a commit numbered C<$num> isn't found, this method will croak.
You can also provide a specific commit SHA-1 checksum to cancel.

For an alternative that doesn't lose information, see C<revert()>.

=cut

sub undo {
	my ($self, $num) = @_;

	my $commit;
	if (defined $num && $num !~ m/^\d+$/) {
		# seems we've been provided with a commit hash, not number
		$commit = $num;
	} else {
		$num ||= 0;
		my $log = $self->log($num+1);
		croak "Can't find commit number $num." unless $log;
		$commit = $log->commit;
	}
	$self->_repo->run('reset', '--hard', $commit);
}

=head2 revert( [ $num ] )

=head2 revert( $commit_checksum )

Reverts the database back to the commit just before the commit performed
C<$num>th commits ago and creates a new commit out of it. In other words,
a snapshot of the database from the source commit (performed C<$num + 1>
commits ago) will be taken and used to replace the database's current
state. Then, a new commit is performed. Thus, the changes performed
between the source commit and the current commit are preserved in the log.
This is different than C<undo()>, which completely removes all commits
performed between the source commit and the current commit. Actually, a
revert can be cancelled by an C<undo()> operation, as it is a commit
in itself.

C<$num> will be zero by default, in which case the latest commit is
reverted.

If a commit numbered C<$num> isn't found, this method will croak.

You can also provide a specific commit SHA-1 checksum.

=cut

sub revert {
	my ($self, $num) = @_;

	my $commit;
	if (defined $num && $num !~ m/^\d+$/) {
		# seems we've been provided with a commit hash, not number
		$commit = $num;
	} else {
		$num ||= 0;
		my $log = $self->log($num);
		croak "Can't find commit number $num." unless $log;
		$commit = $log->commit;
	}
	$self->_repo->run('revert', $commit);
}

=head2 log( [ $num ] )

If C<$num> is provided (can be zero), will return a L<Git::Repository::Log>
object of the commit performed C<$num> commits ago. So 0 will return the
latest commit.

If num isn't provided, will return a L<Git::Repository::Log::Iterator>
object starting from the latest commit.

=cut

sub log {
	my ($self, $num_ago) = @_;

	if (defined $num_ago && $num_ago =~ m/^\d+$/) {
		return Git::Repository::Log::Iterator->new($self->_repo, "HEAD~$num_ago")->next;
	} else {
		return Git::Repository::Log::Iterator->new($self->_repo, 'HEAD');
	}
}

=head1 INTERNAL METHODS

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

=head2 _is_collection( $path )

Returns true if C<$path> is a collection directory. Assumes path exists.

=cut

sub _is_collection {
	my ($self, $path) = @_;

	return $self->_is_directory($path) && !$self->_is_document_dir($path) && !$self->_is_static_dir($path) ? 1 : 0;
}

=head2 _is_document_dir( $path )

Returns true if C<$path> is a document directory. Assumes path exists.

=cut

sub _is_document_dir {
	my ($self, $path) = @_;

	return $self->_is_directory($path) && $self->_path_exists($path.'/'.'attributes.yaml') ? 1 : 0;
}

=head2 _is_static_dir( $path )

Returns true if C<$path> is a static-file directory. Assumes path exists.

=cut

sub _is_static_dir {
	my ($self, $path) = @_;

	return unless $self->_is_directory($path);

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

	perldoc Giddy::Database

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
