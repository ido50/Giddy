package Giddy::Document;

use Any::Moose;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub rel_path {
	$_[0]->collection->path.'/'.$_[0]->name;
}

sub repo {
	$_[0]->collection->giddy->repo;
}

sub attrs {
	my $self = shift;

	return grep {!/^\.gdoc$/} $self->repo->run('ls-tree', '--name-only', "HEAD:".$self->rel_path);
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
