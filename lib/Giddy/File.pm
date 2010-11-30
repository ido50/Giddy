package Giddy::File;

use Any::Moose;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub id {
	$_[0]->name;
}

sub content {
	my $self = shift;

	$self->collection->giddy->repo->run('show', 'HEAD:'.$self->rel_path);
}

sub rel_path {
	my $self = shift;

	return $self->collection->path.'/'.$self->name;
}

sub full_path {
	my $self = shift;

	return $self->collection->giddy->repo->work_tree.'/'.$self->rel_path;
}

sub working_content {
	my $self = shift;

	return $self->collection->futil->load_file($self->full_path);
}

sub attrs {
	'content';
}

sub attr {
	shift->content;
}

__PACKAGE__->meta->make_immutable;
