package Giddy::Document;

use Any::Moose;
use Carp;

has 'collection' => (is => 'ro', isa => 'Giddy::Collection', required => 1);

has 'name' => (is => 'ro', isa => 'Str', required => 1);

sub rel_path {
	my $self = shift;

	return $self->collection->path.'/'.$self->name;
}

sub attr {
	my ($self, $name) = @_;

	# if $name doesn't contain a type, do a find() query and return the first match (if any)
	if ($name =~ m/(.+)\.([^.]+)$/) {
		my ($n, $t) = ($1, $2);
		# have a type, attempt to find it
		if ($self->collection->giddy->repo->run('cat-file', '-t', "HEAD:".$self->rel_path.'/'.$name) eq 'blob') {
			# open this file
			return Giddy::File->new(collection => $self->collection, name => $m, type => $t);
		}
	} else {
		my $find = $self->collection->giddy->find($self->rel_path.'/'.$name);
		if ($find->count) {
			return $find->first;
		}
	}

	return;
}

__PACKAGE__->meta->make_immutable;
