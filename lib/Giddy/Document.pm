package Giddy::Document;

use Any::Moose;
use YAML::Any;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub rel_path {
	$_[0]->collection->path.'/'.$_[0]->name;
}

sub repo {
	$_[0]->collection->giddy->repo;
}

sub meta_data {
	my $self = shift;

	if (grep {/^meta\.yaml$/} $self->repo->run('ls-tree', '--name-only', "HEAD:".$self->rel_path)) {
		# we have a meta file, parse it and return it
		return Load($self->repo->run('show', 'HEAD:'.$self->rel_path.'/meta.yaml'));
	} else {
		return {};
	}
}	

sub attrs {
	my $self = shift;

	return grep {!/^meta\.yaml$/} $self->repo->run('ls-tree', '--name-only', "HEAD:".$self->rel_path);
}

sub attr {
	my ($self, $name) = @_;

	if ($self->repo->run('cat-file', '-t', "HEAD:".$self->rel_path.'/'.$name) eq 'blob') {
		# open this file
		return Giddy::File->new(collection => $self->collection, name => $name);
	}

	return;
}

__PACKAGE__->meta->make_immutable;
