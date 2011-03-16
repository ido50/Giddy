package Giddy::Role::DocumentStorer;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use Fcntl qw/:flock/;
use File::Path qw/make_path/;
use YAML::XS;

requires 'path';
requires '_database';
requires '_spath';

=head1 NAME

Giddy::Role::DocumentStorer - Provides document storing for Giddy::Collection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 _store_document( $filename, \%attributes )

=cut

sub _store_document {
	my ($self, $filename, $attrs) = @_;

	# don't allow the _name attribute
	delete $attrs->{_name};

	if (exists $attrs->{_body}) {
		my $fpath = File::Spec->catfile($self->_database->_repo->work_tree, $self->_spath, $filename);

		my $body = delete $attrs->{_body};

		my $content = '';
		$content .= Dump($attrs) . "\n" if scalar keys %$attrs;
		$content .= $body if $body;
		$content = ' ' unless $content;
		$content =~ s/^---\n//;

		# create the document
		$self->_write_file($fpath, $content, 0664);

		# mark the document for staging
		$self->_database->mark(File::Spec->catfile($self->path, $filename));
	} else {
		my $fpath = File::Spec->catdir($self->_database->_repo->work_tree, $self->_spath, $filename);

		# create the document directory
		make_path($fpath, { mode => 0755 });

		# create the attributes file
		my $yaml = Dump($attrs);
		$yaml =~ s/^---\n//;
		$self->_write_file(File::Spec->catfile($fpath, 'attributes.yaml'), $yaml, 0664);

		# mark the document for staging
		$self->_database->mark(File::Spec->catdir($self->path, $filename));
	}
}

sub _write_file {
	my ($self, $fpath, $content, $mode) = @_;

	# there's no need to open the output file in binary :utf-8 mode,
	# as the YAML Dump() function returns UTF-8 encoded data (so it seems)

	open(FILE, '>', $fpath)
		|| croak "Can't open file $fpath for writing: $!";
	flock(FILE, LOCK_EX);
	print FILE $content;
	close(FILE)
		|| carp "Error closing file $fpath: $!";
	chmod($mode, $fpath);
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
