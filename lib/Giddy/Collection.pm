package Giddy::Collection;

use Any::Moose;
use Carp;

has 'giddy' => (is => 'ro', isa => 'Giddy', required => 1);

has 'path' => (is => 'ro', isa => 'Str', required => 1);

has 'futil' => (is => 'ro', isa => 'File::Util', required => 1);

=head2 new_file( $path_to_file, [$content] )

=cut

sub new_file {
	my ($self, $filename, $content) = @_;

	$content ||= '';

	croak "You must provide a filename for the new file."
		unless $filename;

	croak "File to create already exists."
		if -e $self->giddy->repo->work_tree.'/'.$self->path.'/'.$filename;

	# make sure file has an extension
	if ($filename !~ m/\.([^.]+)$/) {
		$filename .= '.txt';
	}

	# create the file
	$self->futil->write_file(file => $self->giddy->repo->work_tree.'/'.$self->path.'/'.$filename, content => $content);
	chmod 0664, $self->giddy->repo->work_tree.'/'.$self->path.'/'.$filename;

	# mark the file for staging
	$self->giddy->mark($self->path.'/'.$filename);

	my ($name, $type) = ($filename =~ m/^(.+)\.([^.]+)$/);

	return Giddy::File->new(collection => $self, name => $name, type => $type);
}

=head2 new_document( $document_name, \%attributes )

=head2 new_doc( $document_name, \%attributes )

=cut

sub new_document {
	my ($self, $name, $attrs) = @_;

	croak "You must provide a name to the new document."
		unless $name;

	croak "Document to create already exists."
		if -e $self->giddy->repo->work_tree.'/'.$self->path.'/'.$name;

	croak "You must provide a hash-ref of attributes."
		unless $attrs && ref $attrs eq 'HASH';

	my $docpath = $self->giddy->repo->work_tree.'/'.$self->path.'/'.$name;

	mkdir $docpath;
	chmod 0775, $docpath;
	$self->giddy->mark($self->path.'/'.$name.'/');

	foreach (keys %$attrs) {
		$self->futil->write_file(file => $docpath.'/'.$_, content => $attrs->{$_});
		chmod 0664, $docpath.'/'.$_;
	}

	# mark the document's directory as a document directory
	$self->futil->write_file(file => $docpath.'/.gdoc', content => '# a Giddy document');
	chmod 0664, $docpath.'/.gdoc';

	return Giddy::Document->new(collection => $self, name => $name);
}

__PACKAGE__->meta->make_immutable;
