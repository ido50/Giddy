package Giddy::Database;

# ABSTRACT: A Giddy database.

use Any::Moose;
use namespace::autoclean;

use Carp;
use File::Path qw/make_path/;
use Git::Repository;
use Git::Repository::Log::Iterator;
use Giddy::Collection;

=head1 NAME

Giddy::Database - A Giddy database.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 _repo

A L<Git::Repository> object, tied to the git repository of the Giddy database.
This is a required attribute.

=head2 _marked

A list of paths to add to the next commit job. Automatically created.

=cut

has '_repo' => (is => 'ro', isa => 'Git::Repository', required => 1);

has '_marked' => (is => 'ro', isa => 'ArrayRef[Str]', default => sub { [] }, writer => '_set_marked');

=head1 OBJECT METHODS

=head2 get_collection( $path_to_coll )

=cut

sub get_collection {
	my ($self, $path) = @_;

	$path ||= '/';

	# remove trailing slash from path, if exists
	unless ($path eq '/') {
		my $spath = $path;
		# remove trailing slash (if exists)
		$spath =~ s!/$!!;
		# remove starting slash (if exists)
		$spath =~ s!^/!!;

		if (-d File::Spec->catdir($self->_repo->work_tree, $spath) && -e File::Spec->catdir($self->_repo->work_tree, $spath, 'attributes.yaml')) {
			croak "The collection path exists in the database as a document directory, can't load it as a collection.";
		}

		# create the collection directory (unless it already exists)
		make_path(File::Spec->catdir($self->_repo->work_tree, $spath), { mode => 0775 });
	}

	return Giddy::Collection->new(_database => $self, path => $path);
}

=head2 commit( [$commit_msg] )

Commits all pending changes. This actually performs two git operations, the
first being staging the files that were C<mark>ed, and them commiting the
changes.

=cut

sub commit {
	my ($self, $msg) = @_;

	$msg ||= "Commiting ".scalar(@{$self->_marked})." changes";

	# commit
	$self->_repo->run('commit', '-m', $msg);

	# clear marked list
	$self->_set_marked([]);

	return 1;
}

=head2 mark( $path | @paths )

Marks files/directories as to be staged. Mostly called automatically by
C<new_collection()>, C<new_document()>, etc.

=cut

sub mark {
	my ($self, @paths) = @_;

	croak "You must provide the relative path of the file/directory to stage."
		unless scalar @paths;

	foreach (@paths) {
		# remove trailing slash from path, if exists
		s!/$!!;
		# remove starting slash from path, if exists
		s!^/!!;
		
		# stage the file
		$self->_repo->run('add', $_);
	}

	# store files in object
	my $marked = $self->_marked;
	push(@$marked, @paths);
	$self->_set_marked($marked);
}

=head2 find( [ $path, [\%options] ] )

Searches the Giddy repository for documents that match the provided
path. The path has to be relative to the repository's root directory, which
is considered '/'. This string will be used if C<$path> is not provided.

=cut

sub find {
	my ($self, $path, $opts) = @_;

	croak "find() expected a hash-ref of options, but received ".ref($opts)
		if $opts && ref $opts ne 'HASH';

	$opts ||= {};

	# in which directory are we searching?
	my ($dir, $name) = ('/', '');
	if ($path) {
		($name) = ($path =~ m!/([^/]+)$!);
		$name ||= $path;
		$dir = $` || '/';
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

=head2 cancel( [ $num ] )

Cancels the C<$num>th latest commit performed (if $num is 0 or not passed, the
latest commit is cancelled). Any changes performed by the commit cancelled
are forever lost. For an alternative that doesn't lose information, see
C<revert()>.

If a commit numbered C<$num> isn't found, this method will croak.

=cut

sub undo {
	my ($self, $num) = @_;

	$num ||= 0;

	my $log = $self->log($num+1);
	croak "Can't find commit number $num." unless $log;
	$self->_repo->run('reset', '--hard', $log->commit);
}

sub cancel { shift->undo(@_) }

=head2 revert( [ $num ] )

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

=cut

sub revert {
	my ($self, $num) = @_;

	$num ||= 0;

	my $log = $self->log($num);
	croak "Can't find commit number $num." unless $log;
	$self->_repo->run('revert', $log->commit);
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
