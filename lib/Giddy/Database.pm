package Giddy::Database;

# ABSTRACT: A Giddy database.

use Any::Moose;
use namespace::autoclean;

use Carp;
use Git::Repository;
use Git::Repository::Log::Iterator;
use Giddy::Collection;

our $VERSION = "0.012_002";
$VERSION = eval $VERSION;

=head1 NAME

Giddy::Database - A Giddy database.

=head1 SYNOPSIS

	my $db = $giddy->getdb('/path/to/database');

=head1 DESCRIPTION

This class represents Giddy databases. Aside from providing you with the ability
to create and get collections from the database, it provides methods which are
global to the database, like commit changes, undoing changes, etc.

=head1 CONSUMES

L<Giddy::Role::PathAnalyzer>

=head1 ATTRIBUTES

=head2 _repo

A L<Git::Repository> object, tied to the git repository of the Giddy database.
This is a required attribute. Not meant to be used externally, but knock yourself
out if you feel the need to run specific Git commands.

=head2 _staged

A list of paths staged (added) to the next commit job. Automatically created.

=cut

has '_repo' => (is => 'ro', isa => 'Git::Repository', required => 1);

has '_staged' => (is => 'ro', isa => 'ArrayRef[Str]', default => sub { [] }, writer => '_set_staged');

with	'Giddy::Role::PathAnalyzer',
	'Giddy::Role::PathMaker';

=head1 OBJECT METHODS

=head2 get_collection( [ $path_to_coll ] )

Returns a L<Giddy::Collection> object tied to a certain directory in the database.
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
			if $self->_path_exists($path) && ($self->_is_document_dir($path) || $self->_is_static_dir($path));

		# create the collection directory (unless it already exists)
		$self->_create_dir($path);
	}

	return Giddy::Collection->new(db => $self, path => $path);
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
