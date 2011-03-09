package Giddy::Collection;

# ABSTRACT: A Giddy collection.

use Any::Moose;
use namespace::autoclean;

use Carp;
use File::Spec;
use File::Util;
use Giddy::Cursor;
use Tie::IxHash;

has 'path' => (is => 'ro', isa => 'Str', default => '/');

has '_database' => (is => 'ro', isa => 'Giddy::Database', required => 1);

has '_futil' => (is => 'ro', isa => 'File::Util', required => 1);

with	'Giddy::Role::DocumentLoader',
	'Giddy::Role::DocumentMatcher',
	'Giddy::Role::DocumentStorer',
	'Giddy::Role::DocumentUpdater';

=head1 NAME

Giddy::Collection - A Giddy collection.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 path

The relative path of the collection. Defaults to '/', which is the root
directory of the database.

=head2 _database

The L<Giddy::Database> object the collection belongs to. Required.

=head2 _futil

A L<File::Util> object used by the module. Required.

=head2 _mt

A L<MIME::Types> object used by the module. Automatically created.

=head1 OBJECT METHODS

=head2 DOCUMENT QUERYING

=head3 find( [ $name, \%options ] )

Searches the Giddy repository for documents that match the provided
file name. If C<$name> is empty or not provided, every document in the
collection will be matched.

=head3 find( [ \%query, \%options ] )

Searches the Giddy repository for documents that match the provided query.
If no query is given, every document in the collection will be matched.

Both methods return a L<Giddy::Cursor> object.

Searching by name is much faster than searching by query, as Giddy isn't
forced to load and deserialize every document.

=cut

sub find {
	my ($self, $query, $opts) = @_;

	croak "find() expected a hash-ref of options."
		if $opts && ref $opts ne 'HASH';

	$query ||= '';
	$opts ||= {};

	if (ref $query && ref $query eq 'HASH') {
		return $self->_match_by_query($query, $opts);
	} else {
		return $self->_match_by_name($query, $opts);
	}
}

=head3 find_one( [ $name, \%options ] )

Same as calling C<< find($name, $options)->first() >>.

=head3 find_one( [ \%query, \%options ] )

Same as calling C<< find($query, $options)->first() >>.

=cut

sub find_one {
	shift->find(@_)->first;
}

=head3 grep( [ \@strings, \%options ] )

Finds documents whose file contents (ignoring attributes and database YAML
structure) match all (or any, depending on C<\%options>) of the provided
strings. This is much faster than using C<find()> as it simply uses the
git-grep command, but is obviously less useful.

=head3 grep( [ $string, \%options ] )

Finds documents whose file contents (ignoring attributes and database YAML
structure) match the provided string. This is much faster than using C<find()> as it simply uses the
git-grep command, but is obviously less useful.

Both methods return a L<Giddy::Cursor> object.

=cut

sub grep {
	my ($self, $query, $opts) = @_;

	croak "grep() expected a hash-ref of options."
		if $opts && ref $opts ne 'HASH';

	$query ||= [];
	$query = [$query] if !ref $query;
	$opts ||= {};

	my $cursor = Giddy::Cursor->new(_query => { grep => $query, coll => $self, opts => $opts });

	my @cmd = ('grep', '-I', '--name-only', '--max-depth', 1);
	push(@cmd, '--all-match') unless $opts->{'or'}; # that's how we do an 'and' search'
	push(@cmd, '--cached') unless $opts->{'working'};

	if (scalar @$query) {
		foreach (@$query) {
			push(@cmd, '-e', $_);
		}
	} else {
		push(@cmd, '-e', '');
	}

	push(@cmd, { cwd => File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath) }) if $self->_spath;

	my $docs = {};
	if ($opts->{working}) {
		foreach ($self->_database->_repo->run(@cmd)) {
			if (m!/!) {
				next if $docs->{$`};
				$cursor->_add_result({ document_dir => File::Spec->catdir($self->path, $`) });
				$docs->{$`} = 1;
			} else {
				next if $docs->{$_};
				$cursor->_add_result({ document_file => File::Spec->catfile($self->path, $_) });
				$docs->{$_} = 1;
			}
		}
	} else {
		foreach ($self->_database->_repo->run(@cmd)) {
			if (m!/!) {
				next if $docs->{$`};
				$cursor->_add_result({ document_dir => File::Spec->catdir($self->path, $`) });
				$docs->{$`} = 1;
			} else {
				next if $docs->{$_};
				$cursor->_add_result({ document_file => File::Spec->catfile($self->path, $_) });
				$docs->{$_} = 1;
			}
		}
	}

	return $cursor;
}

=head3 grep_one( [ $string, \%options ] )

=head3 grep_one( [ \@strings, \%options ] )

=cut

sub grep_one {
	shift->grep(@_)->first;
}

=head3 count( [ $name, \%options ] )

Shortcut for C<< find($name, $options)->count() >>.

=head3 count( [ \%query, \%options ] )

Shortcut for C<< find($query, $options)->count() >>.

=cut

sub count {
	shift->find(@_)->count;
}

=head2 DOCUMENT MANIPULATION

=head3 insert( $filename, \%attributes )

=cut

sub insert {
	my ($self, $filename, $attrs) = @_;

	croak "You must provide a filename for the new document (that doesn't start with a slash)."
		unless $filename && $filename !~ m!^/!;

	return ($self->batch_insert([$filename => $attrs]))[0];
}

=head3 batch_insert( [ $path1 => \%attrs1, $path2 => \%attrs2, ... ] )

=cut

sub batch_insert {
	my ($self, $docs) = @_;

	# first, make sure the document array is valid
	croak "batch_insert() expects an array-ref of documents."
		unless $docs && ref $docs eq 'ARRAY';
	croak "Odd number of elements in document array, batch_insert() expects an even-numberd array."
		unless scalar @$docs % 2 == 0;

	my $hash = Tie::IxHash->new(@$docs);

	# make sure array is valid and we can actually create all the documents (i.e. they
	# don't already exist) - if even one document is invalid, we don't create any
	foreach my $filename ($hash->Keys) {
		my $attrs = $hash->FETCH($filename);

		croak "You must provide document ${filename}'s attributes as a hash-ref."
			unless $attrs && ref $attrs eq 'HASH';

		if (exists $attrs->{_body}) {
			croak "A document called $filename already exists."
				if -e File::Spec->catfile($self->_database->_repo->work_tree, $self->_spath, $filename);
		} else {
			croak "A document called $filename already exists."
				if -e File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath, $filename);
		}
	}

	my @paths; # will hold paths of all documents created

	# store the documents in the filesystem
	foreach my $filename ($hash->Keys) {
		$self->_store_document($filename, $hash->FETCH($filename));

		# return the document's path
		push(@paths, File::Spec->catdir($self->path, $filename));
	}

	return @paths;
}

=head3 update( $name, \%object, [ \%options ] )

=head3 update( \%query, \%object, [ \%options ] )

=cut

sub update {
	my ($self, $query, $obj, $options) = @_;

	croak "update() requires a query string (can be empty) or hash-ref (can also be empty)."
		unless defined $query;
	croak "update() requires a hash-ref object to update according to."
		unless $obj && ref $obj eq 'HASH';
	croak "update() expects a hash-ref of options."
		if $options && ref $options ne 'HASH';

	$options ||= {};
	$options->{skip_binary} = 1;

	my $cursor = $self->find($query, $options);

	my $updated = { docs => [], n => 0 }; # will be returned to the caller

	# have we found anything? if not, are we upserting?
	if ($cursor->count) {
		my @docs = $options->{multiple} ? $cursor->all : ($cursor->first); # the documents we're updating

		foreach (@docs) {
			my $name = $_->{_name};

			# update the document object
			$self->_update_document($obj, $_);

			# store the document in the file system
			$self->_store_document($name, $_);

			# add info about this update to the $updated hash
			$updated->{n} += 1;
			push(@{$updated->{docs}}, $name);
		}
	} elsif ($options->{upsert} && ref $query eq 'HASH' && $query->{_name} && !ref $query->{_name}) {
		# we can create one document
		my $doc = {};
		$self->_update_document($obj, $doc);

		# store the document in the fs
		$self->_store_document($query->{_name}, $doc);

		# add info about this upsert to the $updated hash
		$updated->{n} = 1;
		$updated->{docs} = [$query->{_name}];
	}

	return $updated;
}

=head3 remove( [ $name, \%options ] )

=head3 remove( [ \%query, \%options ] )

=cut

sub remove {
	my ($self, $query, $options) = @_;

	croak "remove() expects a query string (can be empty) or hash-ref (can also be empty)."
		if defined $query && ref $query && ref $query ne 'HASH';
	croak "remove() expects a hash-ref of options."
		if $options && ref $options ne 'HASH';

	$query ||= '';
	my $cursor = $self->find($query, $options);

	my $deleted = { docs => [], n => 0 };

	# assuming query was a name search and not an attribute search,
	# i don't want to unnecessarily load all document just so i could
	# delete them, so I'm gonna just iterate through the cursor's
	# _results array:
	my @docs = $options->{multiple} ? @{$cursor->_results || []} : $cursor->count ? ($cursor->_results->[0]) : ();
	foreach (@docs) {
		if ($_->{document_file}) {
			# get the file's name and search path
			my $spath = ($_->{document_file} =~ m!^/(.+)$!)[0];
			my $name  = ($_->{document_file} =~ m!/([^/]+)$!)[0];
			
			# remove the file
			$self->_database->_repo->run('rm', '-f', $spath);

			# add some info about this deletion
			$deleted->{n} += 1;
			push(@{$deleted->{docs}}, $name);
		} elsif ($_->{document_dir}) {
			# get the document's name and search path
			my $spath = ($_->{document_dir} =~ m!^/(.+)$!)[0];
			my $name  = ($_->{document_dir} =~ m!/([^/]+)$!)[0];

			# remove the document
			$self->_database->_repo->run('rm', '-r', '-f', $spath);

			# add some info about this deletion
			$deleted->{n} += 1;
			push(@{$deleted->{docs}}, $name);
		}
	}

	return $deleted;
}

=head2 COLLECTION OPERATIONS

=head3 drop()

Removes the collection from the database. Will not work (and croak) on
the root collection.

=cut

sub drop {
	my $self = shift;

	croak "You cannot drop the root collection."
		if $self->path eq '/';

	$self->_database->_repo->run('rm', '-r', '-f', $self->_spath);
}

=head1 INTERNAL METHODS

The following methods are only to be used internally.

=head3 _spath()

=cut

sub _spath {
	($_[0]->path =~ m!^/(.+)$!)[0];
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Collection

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
