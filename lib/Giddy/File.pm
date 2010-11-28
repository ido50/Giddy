package Giddy::File;

use Any::Moose;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub content {
	my $self = shift;

	$self->collection->giddy->repo->run('show', 'HEAD:'.$self->collection->path.'/'.$self->name);
}

sub path {
	my $self = shift;

	return $self->collection->giddy->repo->work_tree.'/'.$self->collection->path.'/'.$self->name;
}

sub working_content {
	my $self = shift;

	return $self->collection->futil->load_file($self->path);
}

__PACKAGE__->meta->make_immutable;
