package Giddy::Role::DocumentLoader;

use Any::Moose 'Role';
use namespace::autoclean;

use Carp;
use Try::Tiny;
use YAML::Any;

requires 'path';
requires '_futil';
requires '_database';
requires '_spath';

=head1 NAME

Giddy::Role::DocumentLoader - Provides document loading methods for Giddy::Collection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head3 _load_document_file( $path, [ $working ] )

=cut

sub _load_document_file {
	my ($self, $path, $working) = @_;

	my $spath = $path;
	$spath =~ s!^/!!;

	my $content = $working ?
		''.$self->_futil->load_file(File::Spec->catfile($self->_database->_repo->work_tree, $path)) :
		''.$self->_database->_repo->run('show', 'HEAD:'.$spath);

	return unless $content;

	my ($yaml, $body) = ('', '');
	if ($content =~ m/\n\n/) {
		($yaml, $body) = ($`, $');
	} else {
		$body = $content;
	}

	return try {
		my $doc = Load($yaml);
		$doc->{_body} = $body;
		$doc->{_name} = ($path =~ m!/([^/]+)$!)[0];
		return $doc;
	} catch {
		return { _body => $body, _name => ($path =~ m!/([^/]+)$!)[0] };
	};
}

=head3 _load_document_dir( $path, [ $working, $skip_binary ] )

=cut

sub _load_document_dir {
	my ($self, $path, $working, $skip_bin) = @_;

	my $spath = $path;
	$spath =~ s!^/!!;

	my $doc;

	my $fpath = File::Spec->catdir($self->_database->_repo->work_tree, $spath);

	if ($working) {
		# try to load the attributes
		my $yaml = $self->_futil->load_file(File::Spec->catfile($fpath, 'attributes.yaml'));
		croak "Can't find/read attributes.yaml file of document $path." unless $yaml;
		$doc = try { Load($yaml) } catch { {} };

		# try to load binary files (unless we're skipping binary)
		unless ($skip_bin) {
			foreach (grep {!/^attributes\.yaml$/} $self->_futil->list_dir($fpath, '--files-only')) {
				$doc->{$_} = File::Spec->catfile($path, $_);
			}
		}
	} else {
		# try to load the attributes
		my $yaml = $self->_database->_repo->run('show', 'HEAD:'.File::Spec->catfile($spath, 'attributes.yaml'));
		croak "Can't find/read attributes.yaml file of document $path." unless $yaml;
		$doc = try { Load($yaml) } catch { {} };

		# try to load binary files (unless we're skipping binary)
		unless ($skip_bin) {
			foreach (grep {!/^attributes\.yaml$/} $self->_database->_repo->run('ls-tree', '--name-only', "HEAD:".$spath)) {
				$doc->{$_} = File::Spec->catfile($path, $_);
			}
		}
	}

	$doc->{_name} = ($path =~ m!/([^/]+)$!)[0] if $doc && scalar keys %$doc;

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
