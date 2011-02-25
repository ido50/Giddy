#!perl

use warnings;
use strict;
use File::Temp qw/tempdir/;
use File::Spec;
use Giddy;
use Test::More;
use Test::Git;

has_git();

plan tests => 23;

my $tmpdir = tempdir(CLEANUP => 1);
diag("Gonna use $tmpdir for the temporary database directory");

# create a new Giddy object
my $g = Giddy->new;
ok($g, 'Got a proper Giddy object');

# create a Giddy database
my $db = $g->get_database($tmpdir);
is(ref($db->_repo), 'Git::Repository', 'Created a new Giddy database');

# create a Giddy collection
my $coll = $db->get_collection('/collection');
is($coll->path, '/collection', 'Created a new Giddy collection');
ok(-d File::Spec->catdir($tmpdir, 'collection'), 'New collection has a directory in the filesystem');

# create some articles
my $html_p = $coll->insert('index.html', { _body => '<h1>Giddy</h1>', user => 'gitguy', date => '12-12-12T12:12:12+03:00' });
is($html_p, '/collection/index.html', 'Created an HTML article');

my $json_p = $coll->insert('index.json', { _body => '{ how: "so" }' });
ok(-e File::Spec->catdir($tmpdir, 'collection', 'index.json'), 'Created a JSON article');

my $text_p = $coll->insert('asdf.txt', { _body => 'asdf', asdf => 'AsDf' });
is($text_p, '/collection/asdf.txt', 'Create a text article');

# commit the changes
$db->commit( "Testing a commit" );

# take a look at the contents of the articles
my $html = $db->find_one($html_p);
is($html->{_body}, '<h1>Giddy</h1>', 'HTML cached content OK');
is($html->{user}, 'gitguy', 'HTML attributes OK');

my $json = $db->find_one($json_p, { working => 1 });
is($json->{_body}, '{ how: "so" }', 'JSON working content OK');

my $text = $db->find_one($text_p);
is($text->{_path}, $text_p, 'Text article loaded OK');

# get the root collection
my $root = $db->get_collection;
is($root->path, '/', 'Root collection received OK');

# create a new document
my $doc_p = $root->insert('about', { 'subject' => 'About Giddy', 'text' => '<p>This is stupid</p>', date => '12-12-12T12:15:56+03:00' });
is($doc_p, '/about', 'Document created OK');
ok(-d File::Spec->catdir($tmpdir, 'about'), 'Document has a directory in the filesystem');
ok(-e File::Spec->catdir($tmpdir, 'about', 'attributes.yaml'), 'Document has an attributes.yaml file');

# search for the document before commiting
my $c1 = $db->find($doc_p);
is($c1->count, 0, 'Document cannot be found before commiting');

# add a fake binary file to the document
open(FILE, ">$tmpdir/about/binary");
print FILE "ASDF";
close FILE;

# commit the changes
$db->commit( "Testing another commit" );

# now find the document
my $doc = $root->find_one('about');
ok($doc, 'Document now found');
is($doc->{'subject'}, 'About Giddy', 'Document loaded OK');
is($doc->{'binary'}, '/about/binary', 'Document has binary reference OK');

# search for some stuff
my $c2 = $db->find('/collection/index.html');
is($c2->count, 1, 'Article found OK');

# drop the collection
$coll->drop;
ok(!-e File::Spec->catdir($tmpdir, 'collection'), 'Collection dropped OK');

# try to drop the root collection (should fail)
eval { $root->drop; };
ok($@ && $@ =~ m/You cannot drop the root collection/, 'Root collection cannot be dropped');

# try to load the about article as a collection (should fail)
eval { $db->get_collection('about'); };
ok($@ && $@ =~ m/The collection path exists in the database as a document directory/, "Can't load a document as a collection");
