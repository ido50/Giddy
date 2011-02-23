package Giddy::Collection;

# ABSTRACT: A Giddy collection.

use Any::Moose;
use namespace::autoclean;

use File::Spec;
use Giddy::Cursor;
use YAML::Any;
use File::Util;
use Try::Tiny;
use MIME::Types;
use Carp;

=head1 NAME

Giddy::Collection - A Giddy collection.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 path

The relative path of the collection. Defaults to an empty string, which
is the root directory of the database.

=head2 _database

The L<Giddy::Database> object the collection belongs to. Required.

=head2 _futil

A L<File::Util> object used by the module. Required.

=head2 _mt

A L<MIME::Types> object used by the module. Automatically created.

=cut

has 'path' => (is => 'ro', isa => 'Str', default => '');

has '_database' => (is => 'ro', isa => 'Giddy::Database', required => 1);

has '_futil' => (is => 'ro', isa => 'File::Util', required => 1);

has '_mt' => (is => 'ro', isa => 'MIME::Types', default => sub { MIME::Types->new });

=head1 OBJECT METHODS

=head2 insert_article( $article_name, [ $body, \%meta ] )

=cut

sub insert_article {
	my ($self, $filename, $body, $meta) = @_;

	croak "You must provide a filename for the new article."
		unless $filename;

	my $fpath = File::Spec->catfile($self->_database->_repo->work_tree, $self->path, $filename);

	croak "An article (or document) called $filename already exists."
		if -e $fpath;

	croak "Meta-data for the article must be a hash-ref"
		if $meta && ref $meta ne 'HASH';

	my $content = '';
	$content .= Dump($meta) . "\n" if $meta && scalar keys %$meta;
	$content .= $body if $body;
	$content = ' ' unless $content;
	$content =~ s/^---\n//;

	# create the article
	$self->_futil->write_file(file => $fpath, content => $content, bitmask => 0664);

	# mark the file for staging
	$self->_database->mark(File::Spec->catfile($self->path, $filename));

	# return the article's path
	if ($self->path) {
		return File::Spec->catfile($self->path, $filename);
	} else {
		return $filename;
	}
}

=head2 insert_document( $document_name, \%attributes, [ \%meta ] )

=cut

sub insert_document {
	my ($self, $name, $attrs, $meta) = @_;

	croak "You must provide a name to the new document."
		unless $name;

	croak "You must provide a hash-ref of attributes."
		unless $attrs && ref $attrs eq 'HASH';

	croak "The meta-data must be a hash-ref."
		if $meta && ref $meta ne 'HASH';

	my $docpath = File::Spec->catdir($self->_database->_repo->work_tree, $self->path, $name);

	croak "A document (or a collection) named $name already exists."
		if -e $docpath;

	# create the document directory
	$self->_futil->make_dir($docpath, 0775);

	# create the attribute files
	foreach (keys %$attrs) {
		$self->_futil->write_file('file' => File::Spec->catfile($docpath, $_), 'content' => $attrs->{$_}, 'bitmask' => 0664);
	}

	# create the meta file
	my $meta_content = $meta ? Dump($meta) : ' ';
	$meta_content =~ s/^---\n//;
	$self->_futil->write_file('file' => File::Spec->catfile($docpath, 'meta.yaml'), 'content' => $meta_content, 'bitmask' => 0664);

	# mark the document for staging
	$self->_database->mark(File::Spec->catdir($self->path, $name));

	# return the document's path
	if ($self->path) {
		return File::Spec->catdir($self->path, $name);
	} else {
		return $name;
	}
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

	my @files = $self->_database->_repo->run('ls-tree', '--name-only', 'HEAD:'.$self->path);
	my $cursor = Giddy::Cursor->new(_query => { path => $path, coll => $self, opts => $opts });

	foreach (@files) {
		# ignore meta.yaml files
		next if $_ eq 'meta.yaml';
		if (m/$path/) {
			my $full_path = $_;
			$full_path = File::Spec->catfile($self->path, $_) if $self->path;
			# what is the type of this thing?
			my $t = $self->_database->_repo->run('cat-file', '-t', "HEAD:$full_path");
			if ($t eq 'tree') {
				# this is either a collection or a document
				if (grep {/^meta\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:$full_path")) {
					# great, this is a document, let's add it
					$cursor->_add_result({ document => $full_path });
				}
			} elsif ($t eq 'blob') {
				# cool, this is an article
				$cursor->_add_result({ article => $full_path });
			}
		}
	}

	return $cursor;
}

=head2 find_one( $path, [\%options] )

=cut

sub find_one {
	shift->find(@_)->first;
}

=head1 INTERNAL METHODS

=head2 _load_article( $path, [ $working ] )

=cut

sub _load_article {
	my ($self, $path, $working) = @_;

	my $content = $working ?
		''.$self->_futil->load_file(File::Spec->catfile($self->_database->_repo->work_tree, $path)) :
		''.$self->_database->_repo->run('show', 'HEAD:'.$path);

	my ($yaml, $body) = ('', '');
	if ($content =~ m/\n\n/) {
		($yaml, $body) = ($`, $');
	} else {
		$body = $content;
	}

	return try {
		my $meta = Load($yaml);
		return { body => $body, meta => $meta, _collection => $self, path => $path };
	} catch {
		return { body => $body, meta => {   }, _collection => $self, path => $path };
	};
}

=head2 _load_document( $path, [ $working ] )

=cut

sub _load_document {
	my ($self, $path, $working) = @_;

	my $doc = { meta => {}, path => $path };

	my $fpath = File::Spec->catdir($self->_database->_repo->work_tree, $path);

	if ($working) {
		# try to load the meta data
		$doc->{meta} = ''.$self->_futil->load_file(File::Spec->catfile($fpath, 'meta.yaml'))
			if -e File::Spec->catfile($fpath, 'meta.yaml');

		# try to load the attributes
		foreach (grep {!/^meta\.yaml$/} $self->_futil->list_dir($fpath, '--files-only')) {
			# determine file type according to extension, ignore attributes with no extension
			my ($ext) = (m/\.([^\.]+)$/);
			next unless $ext;
			my $mime = $self->_mt->mimeTypeOf($ext);
			next unless $mime;
			
			if ($mime->isBinary) {
				$doc->{$_} = File::Spec->catfile($path, $_);
			} else {
				$doc->{$_} = $self->_futil->load_file(File::Spec->catfile($fpath, $_));
			}
		}
	} else {
		# try to load the meta data
		$doc->{meta} = Load($self->_database->_repo->run('show', 'HEAD:'.File::Spec->catfile($path, 'meta.yaml')))
			if grep {/^meta\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$path);

		# try to load attributes (but only load text files, leave paths for binary)
		foreach (grep {!/^meta\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$path)) {
			# determine file type according to extension, ignore attributes with no extension
			my ($ext) = (m/\.([^\.]+)$/);
			next unless $ext;
			my $mime = $self->_mt->mimeTypeOf($ext);
			next unless $mime;
			
			if ($mime->isBinary) {
				$doc->{$_} = File::Spec->catfile($path, $_);
			} else {
				$doc->{$_} = $self->_database->_repo->run('show', 'HEAD:'.File::Spec->catfile($path, $_));
			}
		}
	}

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

Copyright 2010 Ido Perlmuter.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

__PACKAGE__->meta->make_immutable;
