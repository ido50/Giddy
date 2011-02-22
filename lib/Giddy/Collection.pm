package Giddy::Collection;

use Any::Moose;
use Giddy::Cursor;
use YAML::Any;
use Carp;
use File::Util;
use Try::Tiny;

has 'path' => (is => 'ro', isa => 'Str', required => 1);

has '_database' => (is => 'ro', isa => 'Giddy::Database', required => 1);

has '_futil' => (is => 'ro', isa => 'File::Util', default => sub { File::Util->new });

=head2 insert_article( $article_name, [ $body, \%meta ] )

=cut

sub insert_article {
	my ($self, $filename, $body, $meta) = @_;

	croak "You must provide a filename for the new article."
		unless $filename;

	croak "An article called $filename already exists."
		if -e $self->_database->_repo->work_tree.'/'.$self->path.'/'.$filename;

	croak "Meta-data for the article must be a hash-ref"
		if $meta && ref $meta ne 'HASH';

	my $content = '';
	$content .= Dump($meta) . "\n" if $meta && scalar keys %$meta;
	$content .= $body if $body;
	$content = ' ' unless $content;
	$content =~ s/^---\n//;

	# create the article
	$self->_futil->write_file(file => $self->_database->_repo->work_tree.'/'.$self->path.'/'.$filename, content => $content, bitmask => 0664);
	#chmod 0664, $self->_database->_repo->work_tree.'/'.$self->path.'/'.$filename;

	# mark the file for staging
	$self->_database->mark($self->path.'/'.$filename);

	# return the article's path
	return $self->path.'/'.$filename;
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

	my $docpath = $self->_database->_repo->work_tree.'/'.$self->path.'/'.$name;

	croak "A document (or a collection) named $name already exists."
		if -d $docpath;

	# create the attribute files
	foreach (keys %$attrs) {
		$self->_futil->write_file('file' => $docpath.'/'.$_, 'content' => $attrs->{$_}, 'bitmask' => 0664);
		#chmod 0664, $docpath.'/'.$_;
	}

	# create the meta file
	my $meta_content = $meta ? Dump($meta) : ' ';
	$meta_content =~ s/^---\n//;
	$self->_futil->write_file('file' => $docpath.'/meta.yaml', 'content' => $meta_content, 'bitmask' => 0664);
	#chmod 0664, $docpath.'/meta.yaml';

	# mark the document for staging
	mkdir $docpath;
	chmod 0775, $docpath;
	$self->_database->mark($self->path.'/'.$name.'/');

	# return the document's path
	return $self->path.'/'.$name;
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
			$full_path = $self->path.'/'.$_ if $self->path;
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
		''.$self->_futil->load_file($self->_database->_repo->work_tree.'/'.$path) :
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

	if ($working) {
		# try to load the meta data
		$doc->{meta} = ''.$self->_futil->load_file($self->_database->_repo->work_tree.'/'.$path.'/meta.yaml')
			if -e $self->_database->_repo->work_tree.'/'.$path.'/meta.yaml';

		# try to load the attributes
		foreach (grep {!/^meta\.yaml$/} $self->_futil->list_dir($self->_database->_repo->work_tree.'/'.$path, '--files-only')) {
			# only load text files
			my $type = $self->_futil->file_type($self->_database->_repo->work_tree.'/'.$path, '--files-only');
			if ($type eq 'PLAIN' || $type eq 'TEXT') {
				$doc->{$_} = $self->_futil->load_file($self->_database->_repo->work_tree.'/'.$path.'/'.$_);
			} else {
				$doc->{$_} = $path.'/'.$_;
			}
		}
	} else {
		# try to load the meta data
		$doc->{meta} = Load($self->_database->_repo->run('show', 'HEAD:'.$path.'/meta.yaml'))
			if grep {/^meta\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$path);

		# try to load attributes (but only load text files, leave paths for binary)
		foreach ($self->_database->_repo->run('grep', '--cached', '-I', '-l', '-e', '$\'\'', $path)) {
			$doc->{$_} = ''.$_[0]->_database->_repo->run('show', 'HEAD:'.$path.'/'.$_);
		}
		# now load binary files
		foreach (grep {!/^meta\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$path)) {
			next unless $doc->{$_}; # this is a text file we've already loaded
			$doc->{$_} = $path.'/'.$_;
		}
	}

	return $doc;
}

__PACKAGE__->meta->make_immutable;
