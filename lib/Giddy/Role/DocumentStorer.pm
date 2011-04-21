package Giddy::Role::DocumentStorer;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use YAML::XS;

our $VERSION = "0.012_005";
$VERSION = eval $VERSION;

requires 'db';
requires '_path_to';

=head1 NAME

Giddy::Role::DocumentStorer - Provides document storing for Giddy::Collection

=head1 SYNOPSIS

	# used internally

=head1 DESCRIPTION

This role provides document storing capabilities to L<Giddy::Collection> and L<Giddy::Collection::InMemory>.

Requires the attributes 'db' and '_path_to' to be implemented by consuming classes.

=head1 METHODS

=head2 _store_document( $filename, \%attributes )

=cut

sub _store_document {
	my ($self, $filename, $attrs) = @_;

	# don't allow the _name attribute
	delete $attrs->{_name};

	my $fpath = $self->_path_to($filename);
	if (exists $attrs->{_body}) {
		my $body = delete $attrs->{_body};

		my $content = '';
		$content .= Dump($attrs) . "\n" if scalar keys %$attrs;
		$content .= $body if $body;
		$content = ' ' unless $content;
		$content =~ s/^---\n//;

		# create the document
		$self->db->_create_file($fpath, $content, 0664);
	} else {
		# create the document directory
		$self->db->_create_dir($fpath);

		# create the attributes file
		my $yaml = Dump($attrs);
		$yaml =~ s/^---\n//;
		$self->db->_create_file($fpath.'/attributes.yaml', $yaml, 0664);
	}

	# stage the document
	$self->db->stage($fpath);
}

=head1 AUTHOR

Ido Perlmuter, C<< <ido at ido50.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-giddy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Giddy>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Giddy::Role::DocumentStorer

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
