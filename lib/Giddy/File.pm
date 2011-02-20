package Giddy::File;

use Any::Moose;
use YAML::Any;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub id {
	$_[0]->name;
}

sub repo {
	$_[0]->collection->giddy->repo;
}

sub rel_path {
	my $self = shift;

	return $self->collection->path ? $self->collection->path.'/'.$self->name : $self->name;
}

sub full_path {
	my $self = shift;

	return $self->repo->work_tree.'/'.$self->rel_path;
}

sub content {
	''.$_[0]->repo->run('show', 'HEAD:'.$_[0]->rel_path);
}

sub working_content {
	my $self = shift;

	return $self->collection->futil->load_file($self->full_path);
}

sub body {
	my ($self, $working) = @_;

	my $content = $working ? $self->working_content : $self->content;

	# return everything after the meta content, i.e. everything after
	# the first two adjcent newlines
	if ($content =~ m/\n\n/) {
		return $';
	} else {
		# no meta, return everything
		return $content;
	}
}

sub working_body {
	shift->body(1);
}

sub meta_data {
	my ($self, $working) = @_;

	my $content = $working ? $self->working_content : $self->content;

	return {} unless $content =~ m/\n\n/;
	return Load($`);
}

sub working_meta_data {
	shift->meta_data(1);
}

sub attrs {
	('body');
}

sub attr {
	my ($self, $attr) = @_;

	croak "Unknown file attribute $attr."
		unless $attr eq 'body';
	
	return $self->$attr;
}

sub ext {
	my $self = shift;

	my ($ext) = ($self->name =~ m/(\.[^.]+$)/);

	return $ext;
}

__PACKAGE__->meta->make_immutable;
