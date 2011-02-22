package Giddy::Database;

# ABSTRACT: A Giddy database.

use Any::Moose;
use Carp;
use autodie qw/:all/;
use Git::Repository;
use Giddy::Collection;
use Try::Tiny;

=head1 NAME

Giddy::Database - A Giddy database.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 _repo

A L<Git::Repository> object, tied to the git repository of the Giddy database.
This is a required attribute.

=cut

has '_repo' => (is => 'ro', isa => 'Git::Repository', required => 1);

=head1 OBJECT METHODS

=head2 get_collection( $path_to_coll )

=cut

sub get_collection {
	my ($self, $path) = @_;

	# remove trailing slash from path, if exists
	$path =~ s!/$!!;
	# remove starting slash from path, if exists
	$path =~ s!^/!!;

	croak "You must provide the relative path of the collection."
		unless $path;

	croak "Can't find the collection's parent."
		if $path =~ m!/[^/]+$! && !-d $self->_repo->work_tree.'/'.$`;

	# is this an existing collection, or a new one?
	if (-d $self->_repo->work_tree.'/'.$path) {
		# make sure this is a collection and not a document
		croak "Path describes a document and not a collection."
			if -e $self->_repo->work_tree.'/'.$path.'/meta.yaml';

		return Giddy::Collection->new(_database => $self, path => $path);
	} else {
		# create the collection
		mkdir $self->_repo->work_tree.'/'.$path;
		chmod 0775, $self->_repo->work_tree.'/'.$path;

		# mark the directory as to be stages
		$self->mark($path);

		return Giddy::Collection->new(_database => $self, path => $path);
	}
}

=head2 commit( [$commit_msg] )

Commits all pending changes. This actually performs two git operations, the
first being staging the files that were C<mark>ed, and them commiting the
changes.

=cut

sub commit {
	my ($self, $msg) = @_;

	return unless scalar @{$self->{marked}};

	$msg ||= "Commiting ".scalar(@{$self->{marked}})." changes";

	# stage the files
	foreach (@{$self->{marked}}) {
		$self->_repo->run('add', $_);
	}

	# commit
	$self->_repo->run('commit', '-m', $msg);

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
	}

	push(@{$self->{marked}}, @paths);
}

=head2 find( [ $path, [\%options] ] )

Searches the Giddy repository for I<anything> that matches the provided
path. The path has to be relative to the repository's root directory, which
is considered the empty string. The empty string will be used if a path
is not provided.

=cut

sub find {
	my ($self, $path, $opts) = @_;

	croak "find() expected a hash-ref for options, but received ".ref($opts)
		if $opts && ref $opts ne 'HASH';

	$path ||= '';
	$opts ||= {};

	# in which directory are we searching?
	my ($file) = ($path =~ m!/([^/]+)$!);
	$file = $path unless $file;
	my $dir = $` || '';
	$dir =~ s!^/!!;

	print STDERR "Searching for $file in $dir\n";

	return $self->get_collection($dir)->find($file, $opts);
}

=head2 find_one( $path, [\%options] )

=cut

sub find_one {
	shift->find(@_)->first;
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

Copyright 2010 Ido Perlmuter.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

__PACKAGE__->meta->make_immutable;
