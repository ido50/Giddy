package Giddy::Role::DocumentLoader;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use Encode;
use Try::Tiny;
use YAML::XS;

our $VERSION = "0.012_005";
$VERSION = eval $VERSION;

requires 'db';
requires '_path_to';

=head1 NAME

Giddy::Role::DocumentLoader - Provides document loading methods for Giddy::Collection

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides document loading capabilities to L<Giddy::Collection> and L<Giddy::Collection::InMemory>.

Requires the attributes 'db' and '_path_to' to be implemented by consuming classes.

=head1 METHODS

=head3 _load_document_file( $name )

=cut

sub _load_document_file {
	my ($self, $name) = @_;

	my $content = ''.$self->db->_repo->run('show', 'HEAD:'.$self->_path_to($name));

	my ($yaml, $body) = ('', '');
	if ($content && $content =~ m/\n\n/) {
		($yaml, $body) = ($`, $');
	} else {
		$body = $content;
	}

	return try {
		my $doc = Load("---\n$yaml");
		$doc->{_body} = $body;
		$doc->{_name} = $name;
		return $doc;
	} catch {
		return { _body => $body, _name => $name };
	};
}

=head3 _load_document_dir( $name, [ $skip_binary ] )

=cut

sub _load_document_dir {
	my ($self, $name, $skip_bin) = @_;

	my $doc;

	# try to load the attributes
	my $yaml = $self->db->_repo->run('show', 'HEAD:'.$self->_path_to($name, 'attributes.yaml'));
	croak "Can't find/read attributes.yaml file of document $name." unless $yaml;
	$doc = try { Load($yaml) } catch { {} };

	# load child collections
	$doc->{_has_many} = [sort grep { !$self->db->_is_document_dir($self->_path_to($name, $_)) && !$self->db->_is_static_dir($self->_path_to($name, $_)) } $self->db->_list_dirs($self->_path_to($name))];

	# load child documents
	$doc->{_has_one} = [sort grep { $self->db->_is_document_dir($self->_path_to($name, $_)) } $self->db->_list_dirs($self->_path_to($name))];

	# try to load binary files (unless we're skipping binary)
	unless ($skip_bin) {
		foreach (grep { $_ ne 'attributes.yaml' } $self->db->_list_files($self->_path_to($name))) {
			$doc->{$_} = $self->_path_to($name, $_);
		}
	}

	$doc->{_name} = $name
		if $doc && scalar keys %$doc;

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

	perldoc Giddy::Role::DocumentLoader

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

1;
