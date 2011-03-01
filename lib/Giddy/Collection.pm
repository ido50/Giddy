package Giddy::Collection;

# ABSTRACT: A Giddy collection.

use Any::Moose;
use namespace::autoclean;

use File::Spec;
use Giddy::Cursor;
use YAML::Any;
use File::Util;
use Try::Tiny;
use Carp;

with 'Giddy::Role::QueryParser';

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

=cut

has 'path' => (is => 'ro', isa => 'Str', default => '/');

has '_database' => (is => 'ro', isa => 'Giddy::Database', required => 1);

has '_futil' => (is => 'ro', isa => 'File::Util', required => 1);

=head1 OBJECT METHODS

=head2 insert( $filename, \%attributes )

=cut

sub insert {
	my ($self, $filename, $attrs) = @_;

	croak "You must provide a filename for the new document (that doesn't start with a slash)."
		unless $filename && $filename !~ m!^/!;

	croak "You must provide the document's attributes as a hash-ref."
		unless $attrs && ref $attrs eq 'HASH';

	if (exists $attrs->{_body}) {
		my $fpath = File::Spec->catfile($self->_database->_repo->work_tree, $self->spath, $filename);
		croak "A document called $filename already exists."
			if -e $fpath;

		my $body = delete $attrs->{_body};

		my $content = '';
		$content .= Dump($attrs) . "\n" if scalar keys %$attrs;
		$content .= $body if $body;
		$content = ' ' unless $content;
		$content =~ s/^---\n//;

		# create the document
		$self->_futil->write_file(file => $fpath, content => $content, bitmask => 0664);

		# mark the document for staging
		$self->_database->mark(File::Spec->catfile($self->path, $filename));
	} else {
		my $fpath = File::Spec->catdir($self->_database->_repo->work_tree, $self->spath, $filename);
		croak "A document called $filename already exists."
			if -e $fpath;

		# create the document directory
		$self->_futil->make_dir($fpath, 0775);

		# create the attributes file
		my $yaml = Dump($attrs);
		$yaml =~ s/^---\n//;
		$self->_futil->write_file('file' => File::Spec->catfile($fpath, 'attributes.yaml'), 'content' => $yaml, 'bitmask' => 0664);

		# mark the document for staging
		$self->_database->mark(File::Spec->catdir($self->path, $filename));
	}

	# return the document's path
	return File::Spec->catdir($self->path, $filename);
}

=head2 get( [ $path, [\%options] ] )

Searches the Giddy repository for I<anything> that matches the provided
path. The path has to be relative to the repository's root directory, which
is considered the empty string. The empty string will be used if a path
is not provided.

=cut

sub get {
	my ($self, $path, $opts) = @_;

	croak "find() expected a hash-ref for options, but received ".ref($opts)
		if $opts && ref $opts ne 'HASH';

	$path = '' if !$path || $path eq '/';
	$opts ||= {};

	my @files = $opts->{working} ? $self->_futil->list_dir(File::Spec->catdir($self->_database->_repo->work_tree, $self->spath)) : $self->_database->_repo->run('ls-tree', '--name-only', $self->spath ? 'HEAD:'.$self->spath : 'HEAD:');
	my $cursor = Giddy::Cursor->new(_query => { path => $path, coll => $self, opts => $opts });

	# what kind of match are we performing? do we search for things
	# that start with $path, or do we search for $path anywhere?
	my $re = $opts->{prefix} ? qr/^$path/ : qr/$path/;

	foreach (@files) {
		if (m/$re/) {
			my $full_path = File::Spec->catfile($self->path, $_);
			my $search_path = ($full_path =~ m!^/(.+)$!)[0];

			if ($opts->{working}) {
				# what is the type of this thing?
				if (-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path) && -e File::Spec->catfile($self->_database->_repo->work_tree, $search_path, 'attributes.yaml')) {
					# this is a document directory
					$cursor->_add_result({ document_dir => $full_path });
				} elsif (!-d File::Spec->catdir($self->_database->_repo->work_tree, $search_path)) {
					# this is a document file
					$cursor->_add_result({ document_file => $full_path });
				}
			} else {
				# what is the type of this thing?
				my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$search_path");
				if ($t eq 'tree') {
					# this is either a collection or a document
					if (grep {/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$search_path")) {
						# great, this is a document directory, let's add it
						$cursor->_add_result({ document_dir => $full_path });
					}
				} elsif ($t eq 'blob') {
					# cool, this is a document file
					$cursor->_add_result({ document_file => $full_path });
				}
			}
		}
	}

	return $cursor;
}

=head2 get_one( $path, [ \%options ] )

=cut

sub get_one {
	shift->get(@_)->first;
}

=head2 find( [ \%query, \%options ] )

=cut

sub find {
	my ($self, $query, $opts) = @_;

	$query ||= {};
	$opts ||= {};

	my $cursor = Giddy::Cursor->new(_query => { coll => $self, opts => $opts });

	if ($opts->{working}) {
		foreach ($self->_futil->list_dir(File::Spec->catdir($self->_database->_repo->work_tree, $self->spath))) {
			my $fs_path = File::Spec->catfile($self->_database->_repo->work_tree, $self->spath, $_);
			my $full_path = File::Spec->catfile($self->path, $_);

			# what is the type of this doc?
			my $t;
			if (-d $fs_path && -e File::Spec->catfile($fs_path, 'attributes.yaml')) {
				# this is a document dir
				my $doc = $self->_load_document_dir($full_path, 1);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_dir => $full_path });
					$cursor->_add_loaded($doc);
				}
			} elsif (!-d $fs_path) {
				# this is a document file
				my $doc = $self->_load_document_file($full_path, 1);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_dir => $full_path });
					$cursor->_add_loaded($doc);
				}
			}
		}
	} else {
		foreach ($self->_database->_repo->run('ls-tree', '--name-only', $self->spath ? 'HEAD:'.$self->spath : 'HEAD:')) {
			my $full_path = File::Spec->catfile($self->path, $_);
			my $search_path = ($full_path =~ m!^/(.+)$!)[0];

			# what is the type of this thing?
			my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$search_path");
			if ($t eq 'tree') {
				# this is either a collection or a document
				if (grep {/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$search_path")) {
					# great, this is a document directory, let's add it
					my $doc = $self->_load_document_dir($full_path);
					if ($self->_document_matches($doc, $query)) {
						$cursor->_add_result({ document_dir => $full_path });
						$cursor->_add_loaded($doc);
					}
				}
			} elsif ($t eq 'blob') {
				# cool, this is a document file
				my $doc = $self->_load_document_file($full_path);
				if ($self->_document_matches($doc, $query)) {
					$cursor->_add_result({ document_file => $full_path });
					$cursor->_add_loaded($doc);
				}
			}
		}
	}

	return $cursor;
}

=head2 find_one( [ \%query, \%options ] )

=cut

sub find_one {
	shift->find(@_)->first;
}

=head2 grep( \@query, [ \%options ] )

=cut

sub grep {
	my ($self, $query, $opts) = @_;

	$query ||= [];
	$opts ||= {};

	my $cursor = Giddy::Cursor->new(_query => { coll => $self, opts => $opts });

	my @query_str;
	foreach (@$query) {
		if (ref $_ eq 'ARRAY') {
			my $str = '( ';
			foreach my $re (@$_) {
				$str .= "-e '$re'";
			}
			$str .= ' )';
			push(@query_str, $str);
		} elsif (!ref $_) {
			push(@query_str, "-e '$_'");
		}
	}

	# WE NEED TO SEARCH BOTH IN DOCUMENT FILES (EASY) AND ALSO IN
	# DOCUMENT DIRS (HARD), SO WE NEED TO FIRST MAKE AN git-ls-tree COMMAND
	# TO GET A LIST OF DIRECTORIES IN THE COLLECTION AND GO OVER IT, WHEN WE
	# SEE A DIRECTORY THAT HAS attributes.yaml IN IT, WE RUN git-grep ON IT.
	# WE ALSO RUN git-grep ON THE COLLECTION'S DIRECTORY TO FIND FILES
	# THAT MATCH THE QUERY

	#my @files = $opts->{working} ? $self->_database->_repo->run('grep', '--name-only', join(' --and ', @query_str), $self->spath) : $self->_database->_repo->run('grep', '--name-only', '--cached', join(' --and ', @query_str), $self->spath);

	return $cursor;
}

=head2 spath()

Returns the path of the collection, without the starting slash.

=cut

sub spath {
	($_[0]->path =~ m!^/(.+)$!)[0];
}

=head2 drop()

Removes the collection from the database. Will not work (and croak) on
the root collection.

=cut

sub drop {
	my $self = shift;

	croak "You cannot drop the root collection."
		if $self->path eq '/';

	$self->_database->_repo->run('rm', '-r', '-f', $self->spath);
}

=head1 INTERNAL METHODS

=head2 _load_document_file( $path, [ $working ] )

=cut

sub _load_document_file {
	my ($self, $path, $working) = @_;

	my $spath = $path;
	$spath =~ s!^/!!;

	my $content = $working ?
		''.$self->_futil->load_file(File::Spec->catfile($self->_database->_repo->work_tree, $path)) :
		''.$self->_database->_repo->run('show', 'HEAD:'.$spath);

	return unless $content;

	my ($yaml, $body) = ('', '');
	if ($content =~ m/\n\n/) {
		($yaml, $body) = ($`, $');
	} else {
		$body = $content;
	}

	return try {
		my $doc = Load($yaml);
		$doc->{_body} = $body;
		$doc->{_path} = $path;
		return $doc;
	} catch {
		return { _body => $body, _path => $path };
	};
}

=head2 _load_document_dir( $path, [ $working ] )

=cut

sub _load_document_dir {
	my ($self, $path, $working) = @_;

	my $spath = $path;
	$spath =~ s!^/!!;

	my $doc;

	my $fpath = File::Spec->catdir($self->_database->_repo->work_tree, $spath);

	if ($working) {
		# try to load the attributes
		my $yaml = $self->_futil->load_file(File::Spec->catfile($fpath, 'attributes.yaml'));
		croak "Can't find/read attributes.yaml file of document $path." unless $yaml;
		$doc = try { Load($yaml) } catch { {} };

		# try to load binary files
		foreach (grep {!/^attributes\.yaml$/} $self->_futil->list_dir($fpath, '--files-only')) {
			$doc->{$_} = File::Spec->catfile($path, $_);
		}
	} else {
		# try to load the attributes
		my $yaml = $self->_database->_repo->run('show', 'HEAD:'.File::Spec->catfile($spath, 'attributes.yaml'));
		croak "Can't find/read attributes.yaml file of document $path." unless $yaml;
		$doc = try { Load($yaml) } catch { {} };

		# try to load binary files
		foreach (grep {!/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$spath)) {
			$doc->{$_} = File::Spec->catfile($path, $_);
		}
	}

	$doc->{_path} = $path if $doc && scalar keys %$doc;

	return $doc;
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
