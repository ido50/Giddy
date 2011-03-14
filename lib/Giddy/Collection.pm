package Giddy::Collection;

# ABSTRACT: A Giddy collection.

use Any::Moose;
use namespace::autoclean;

use Carp;
use File::Spec;
use File::Util;
use Giddy::Collection::InMemory;
use Tie::IxHash;

use Data::Dumper;

has 'path' => (is => 'ro', isa => 'Str', default => '/');

has '_database' => (is => 'ro', isa => 'Giddy::Database', required => 1);

has '_futil' => (is => 'ro', isa => 'File::Util', required => 1);

has '_loc' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_loc');

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

=head2 _loc

An integer representing the current location of the iterator in the results array.
Not to be used externally.

=head1 OBJECT METHODS

=head2 DOCUMENT QUERYING

=head3 find( [ \%query, \%options ] )

Searches the collection for documents that match the provided query.
If no query is given, every document in the collection will be matched.

=head3 find( [ $name, \%options ] )

Searches the collection for documents (more correctly "a document")
whoe name equals C<$name>. This is a shortcut for C<< find({ _name => $name }, $options) >>.

=head2 find( [ $regex, \%options ] )

Searches the collection for documents whose name matches the regular
expression provided. This is a shortcut for C<< find({ _name => qr/some_regex/ }, $options >>.

Searching just by name (either for equality or with a regex) is much faster
than searching by query, as Giddy isn't forced to load and deserialize
every document.

=cut

sub find {
	my ($self, $query, $opts) = @_;

	croak "find() expects either a scalar, a regex or a hash-ref for the query."
		if defined $query && ref $query && ref $query ne 'HASH' && ref $query ne 'Regexp';

	croak "find() expected a hash-ref of options."
		if defined $opts && ref $opts ne 'HASH';

	$query ||= '';
	$opts ||= {};

	$query = { _name => $query } if !ref $query || ref $query eq 'Regexp';

	# stage 1: create an in-memory collection
	my $coll = Giddy::Collection::InMemory->new(
		path => $self->path,
		_database => $self->_database,
		_futil => $self->_futil,
		_query => { find => $query, coll => $self, opts => $opts },
		_documents => $self->isa('Giddy::Collection::InMemory') ? $self->_documents() : $self->_documents($opts->{working})
	);

	# stage 2: are we matching by name? we do if query is a scalar
	# or if the query hash-ref has the _name key
	if (exists $query->{_name}) {
		# let's find documents that match this name
		$coll->_set_documents($self->_match_by_name(delete($query->{_name}), $opts));
	}

	# stage 3: are we querying by document attributes too?
	$coll->_set_documents($coll->_match_by_query($query, $opts))
		if scalar keys %$query;

	return $coll;
}

=head3 find_one( [ $query, \%options ] )

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

	my $coll = Giddy::Collection::InMemory->new(
		path => $self->path,
		_database => $self->_database,
		_futil => $self->_futil,
		_query => { grep => $query, coll => $self, opts => $opts }
	);

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

	my @docs;
	my $docs = {};
	foreach ($self->_database->_repo->run(@cmd)) {
		# ignore documents which aren't in the collection (ugly hack for in-memory collections)
		if (m!/!) {
			next unless $self->document_exists($`, $opts->{working});
			next if $docs->{$`};
			push(@docs, [{ document_dir => File::Spec->catdir($self->path, $`) }]);
			$docs->{$`} = 1;
		} else {
			next unless $self->document_exists($_, $opts->{working});
			next if $docs->{$_};
			push(@docs, [{ document_file => File::Spec->catfile($self->path, $_) }]);
			$docs->{$_} = 1;
		}
	}

	$coll->_set_documents(\@docs);

	return $coll;
}

=head3 grep_one( [ $string, \%options ] )

=head3 grep_one( [ \@strings, \%options ] )

Same as calling C<< grep( $string(s), $options)->first >>.

=cut

sub grep_one {
	shift->grep(@_)->first;
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
	# _documents array:
	my @docs = $options->{multiple} ? @{$cursor->_documents || []} : $cursor->count ? ($cursor->_documents->[0]) : ();
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

=head2 document_exists( $name, [ $working ] )

Returns a true value if a document named C<$named> exists in the collection.
Useful for in-memory collections. If C<$working> is passed with a true
value, search will be performed in the collection's working directory.

=cut

sub document_exists {
	my ($self, $name, $working) = @_;

	my $path = File::Spec->catfile($self->path, $name);
	foreach ($self->isa('Giddy::Collection::InMemory') ? @{$self->_documents} : @{$self->_documents($working)}) {
		my $f = $_->{document_dir} || $_->{document_file};
		return 1 if $f eq $path;
	}

	return;
}

=head2 DOCUMENTS ITERATION

=head3 count()

Returns the number of documents in the collection.

=cut

sub count {
	scalar shift->_documents;
}

=head3 all()

Returns an array of all the documents in the collection (after loading).

=cut

sub all {
	my $self = shift;
	my @results;
	while ($self->has_next) {
		push(@results, $self->next);
	}
	return @results;
}

=head3 has_next()

Returns a true value if the iterator hasn't reached the last of the documents
(and thus C<next()> can be called).

=cut

sub has_next {
	$_[0]->_loc < $_[0]->count;
}

=head3 next()

Returns the document found by the query from the iterator's current
position, and increases the iterator to point to the next document.

=cut

sub next {
	my $self = shift;

	return unless $self->has_next;

	my $next = $self->_load_document($self->_documents->[$self->_loc]);
	$self->_inc_loc;
	return $next;
}

=head2 rewind()

Resets to iterator to point to the first document.

=cut

sub rewind {
	$_[0]->_set_loc(0);
}

=head2 first()

Returns the first document in the collection (or C<undef> if none exist),
regardless of the iterator's current position (which will not change).

=cut

sub first {
	my $self = shift;

	return unless $self->count;

	return $self->_load_document($self->_documents->[0]);
}

=head2 last()

Returns the last document in the collection (or C<undef> if none exist),
regardless of the iterator's current position (which will not change).

=cut

sub last {
	my $self = shift;

	return unless $self->count;

	return $self->_load_document($self->_documents->[$self->count - 1]);
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

=head2 _spath()

=cut

sub _spath {
	($_[0]->path =~ m!^/(.+)$!)[0];
}

=head2 _documents( [ $working ] )

Returns an array-ref of all documents in the collection. If C<$working> is true,
the list returned will be of all documents in the collection's working
directory, otherwise - only cached documents will be returned.

=cut

sub _documents {
	my ($self, $working) = @_;

	my $docs = [];
	foreach ($working ? sort($self->_futil->list_dir(File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath))) : sort($self->_database->_repo->run('ls-tree', '--name-only', $self->_spath ? 'HEAD:'.$self->_spath : 'HEAD:'))) {
		my $full_path = File::Spec->catfile($self->path, $_);
		my $search_path = ($full_path =~ m!^/(.+)$!)[0];

		if ($working) {
			# what is the type of this thing?
			if (-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path) && -e File::Spec->catfile($self->_database->_repo->work_tree, $search_path, 'attributes.yaml')) {
				# this is a document directory
				push(@$docs, { document_dir => $full_path });
			} elsif (!-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path)) {
				# this is a document file
				push(@$docs, { document_file => $full_path });
			}
		} else {
			# what is the type of this thing?
			my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$search_path");
			if ($t eq 'tree') {
				# this is either a collection or a document
				if (grep {/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$search_path")) {
					# great, this is a document directory, let's add it
					push(@$docs, { document_dir => $full_path });
				}
			} elsif ($t eq 'blob') {
				# cool, this is a document file
				push(@$docs, { document_file => $full_path });
			}
		}
	}

	return $docs;
}

=head2 _inc_loc()

Increases the iterator's position by one.

=cut

sub _inc_loc {
	my $self = shift;

	$self->_set_loc($self->_loc + 1);
}

=head2 _load_document( \%res )

Loads a document from the collection.

=cut

sub _load_document {
	my ($self, $dochash) = @_;

	if ($dochash->{document_file}) {
		if (exists $self->_loaded->{$dochash->{document_file}}) {
			return $self->_loaded->{$dochash->{document_file}};
		} else {
			my $doc = $self->_query->{coll}->_load_document_file($dochash->{document_file}, $self->_query->{opts}->{working});
			$self->_add_loaded($dochash->{document_file}, $doc);
			return $doc;
		}
	} elsif ($dochash->{document_dir}) {
		if (exists $self->_loaded->{$dochash->{document_dir}}) {
			return $self->_loaded->{$dochash->{document_dir}};
		} else {
			my $doc = $self->_query->{coll}->_load_document_dir($dochash->{document_dir}, $self->_query->{opts}->{working}, $self->_query->{opts}->{skip_binary});
			$self->_add_loaded($dochash->{document_dir}, $doc);
			return $doc;
		}
	}
}

=head2 _add_loaded( $path, \%doc )

Adds the loaded document to the cursor

=cut

sub _add_loaded {
	my ($self, $path, $doc) = @_;

	$self->_loaded->{$path} = $doc;
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
