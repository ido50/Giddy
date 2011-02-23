#!perl

use warnings;
use strict;
use File::Temp qw/tempdir/;
use File::Spec;
use Giddy;
use Test::More;
use Test::Git;

has_git();

plan tests => 20;

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
is($coll->path, 'collection', 'Created a new Giddy collection');
ok(-d File::Spec->catdir($tmpdir, 'collection'), 'New collection has a directory in the filesystem');

# create some articles
my $html_p = $coll->insert_article('index.html', '<h1>Giddy</h1>', { user => 'gitguy', date => '12-12-12T12:12:12+03:00' });
is($html_p, 'collection/index.html', 'Created an HTML article');

my $json_p = $coll->insert_article('index.json', '{ how: "so" }');
ok(-e File::Spec->catdir($tmpdir, 'collection', 'index.json'), 'Created a JSON article');

my $text_p = $coll->insert_article('asdf.txt', 'asdf', { asdf => 'AsDf' });
is($text_p, 'collection/asdf.txt', 'Create a text article');

# commit the changes
$db->commit( "Testing a commit" );

# take a look at the contents of the articles
my $html = $db->find_one($html_p);
is($html->{body}, '<h1>Giddy</h1>', 'HTML cached content OK');
is(ref($html->{meta}), 'HASH', 'HTML meta is a hash-ref');
is($html->{meta}->{user}, 'gitguy', 'HTML meta hash-ref OK');

my $json = $db->find_one($json_p, { working => 1 });
is($json->{body}, '{ how: "so" }', 'JSON working content OK');

my $text = $db->find_one($text_p);
is($text->{path}, $text_p, 'Text article loaded OK');

# get the root collection
my $root = $db->get_collection;
is($root->path, '', 'Root collection received OK');

# create a new document
my $doc_p = $root->insert_document('about', { 'subject.txt' => 'About Giddy', 'text.html' => '<p>This is stupid</p>' }, { date => '12-12-12T12:15:56+03:00' });
is($doc_p, 'about', 'Document created OK');
ok(-d File::Spec->catdir($tmpdir, 'about'), 'Document has a directory in the filesystem');
ok(-e File::Spec->catdir($tmpdir, 'about', 'meta.yaml'), 'Document has a meta.yaml file');

# search for the document before commiting
my $c1 = $db->find($doc_p);
is($c1->count, 0, 'Document cannot be found before commiting');

# commit the changes
$db->commit( "Testing another commit" );

# now find the document
my $doc = $db->find_one($doc_p);
ok($doc, 'Document now found');
is($doc->{'subject.txt'}, 'About Giddy', 'Document loaded OK');

# search for some stuff
my $c2 = $db->find('/collection/index.html');
is($c2->count, 1, 'Article found OK');
