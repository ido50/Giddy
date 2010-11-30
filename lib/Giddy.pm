package Giddy;

use Any::Moose;
use Carp;
use autodie qw/:all/;
use Git::Repository;
use File::Util;
use Giddy::Collection;
use Giddy::File;
use Giddy::Document;
use Giddy::Cursor;

# ABSTRACT: Schemaless, versioned document store based on Git.

has 'repo' => (is => 'ro', isa => 'Git::Repository', required => 1);

has 'futil' => (is => 'ro', isa => 'File::Util', default => sub { File::Util->new });

=head1 NAME

Giddy - Schemaless, versioned document store based on Git.

=head1 SYNOPSIS

=head1 CLASS METHODS

=head2 new( $path_to_repo )

=head2 load( $path_to_repo )

Loads a Giddy repository. C<load()> is provided as an alias to C<new()>.
Path must be to a checked out git repository (i.e. not a bare one).

=cut

around BUILDARGS => sub {
	my ($orig, $class, $path) = @_;

	# remove trailing slash, if exists
	$path ||= '';
	$path =~ s!/$!!;

	croak "You must provide a path to the Giddy repository to load."
		unless $path;

	croak "Provided Giddy path doesn't exist or isn't a directory."
		unless -d $path;

	# attempt to load the repo
	my $repo = Git::Repository->new( work_tree => $path );

	return $class->$orig(repo => $repo);
};

=head2 create( $path_to_repo )

Creates a new Giddy repository in the path specified and returns the new
Giddy object.

=cut

sub create {
	my ($class, $path) = @_;

	# remove trailing slash, if exists
	$path =~ s!/$!!;

	croak "You must provide a path in which to create the Giddy repository."
		unless $path;

	croak "Path to new Giddy repository already exists."
		if -e $path;

	# create the new repo
	my $repo = Git::Repository->create(init => $path);

	return $class->new($path);
}

=head1 OBJECT METHODS

=head2 mark( $path | @paths )

Marks files/directories as to be stages. Mostly called automatically by
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
	}

	push(@{$self->{marked}}, @paths);
}

=head2 new_collection( $path_to_coll )

=head2 new_col( $path_to_coll )

Creates a new collection in the repository. Path must be a relative path
to the new directory. The parent of the new collection must already exist.

=cut

sub new_collection {
	my ($self, $path) = @_;

	# remove trailing slash from path, if exists
	$path =~ s!/$!!;
	# remove starting slash from path, if exists
	$path =~ s!^/!!;

	croak "You must provide the relative path of the new collection."
		unless $path;

	if ($path =~ m!/[^/]+$!) {
		croak "Parent of new collection doesn't exist."
			unless -d $self->repo->work_tree.'/'.$`;
	}

	# create the collection
	mkdir $self->repo->work_tree.'/'.$path;
	chmod 0775, $self->repo->work_tree.'/'.$path;

	# mark the directory as to be stages
	$self->mark($path);

	return Giddy::Collection->new(giddy => $self, path => $path, futil => $self->futil);
}

=head2 commit( [$commit_msg] )

Commits all pending changes. This actually performs two git options, the
first being staging the files that were C<mark>ed, and them commiting the
changes.

=cut

sub commit {
	my ($self, $msg) = @_;

	return unless scalar @{$self->{marked}};

	$msg ||= "Commiting ".scalar(@{$self->{marked}})." changes";

	# stage the files
	foreach (@{$self->{marked}}) {
		$self->repo->run('add', $_);
	}

	# commit
	$self->repo->run('commit', '-m', $msg);

	return 1;
}

=head2 find( $path, [\%options] )

=cut

sub find {
	my ($self, $path, $opts) = @_;

	croak "You must provide a path to find."
		unless $path;

	$opts ||= {};

	# in which directory are we searching?
	my ($file) = ($path =~ m!/([^/]+)$!);
	my $dir = $` || '';
	$dir =~ s!^/!!;
	my $collection = Giddy::Collection->new(giddy => $self, path => $dir, futil => $self->futil);

	my @files = $self->repo->run('ls-tree', '--name-only', "HEAD:$dir");
	my $cursor = Giddy::Cursor->new(query => { type => 'find', in => $path, opts => $opts });

	foreach (@files) {
		if (m/$file/) {
			my $full_path = $_;
			$full_path = $dir.'/'.$_ if $dir;
			# what is the type of this thing?
			my $t = $self->repo->run('cat-file', '-t', "HEAD:$full_path");
			if ($t eq 'tree') {
				# this is either a collection or a document,
				# and we need to ignore documents, which are
				# marked with a .gdoc file
				if ($self->repo->run('cat-file', '-t', "HEAD:$full_path/.gdoc") eq 'blob') {
					# great, this is a document, let's add it
					$cursor->_add_result(Giddy::Document->new(collection => $collection, name => $_));
				}
			} elsif ($t eq 'blob') {
				# cool, this is a file
				$cursor->_add_result(Giddy::File->new(collection => $collection, name => $_));
			}
		}
	}

	return $cursor;
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
