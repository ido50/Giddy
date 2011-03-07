#!perl

use warnings;
use strict;
use File::Temp qw/tempdir/;
use File::Spec;
use Giddy;
use Test::More;
use Test::Git;

has_git();

plan tests => 50;

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

# take a look at the contents of the articles
my $html = $db->find_one($html_p, { working => 1 });
is($html->{_body}, '<h1>Giddy</h1>', 'HTML cached content OK');
is($html->{user}, 'gitguy', 'HTML attributes OK');

my $json = $db->find_one($json_p, { working => 1 });
is($json->{_body}, '{ how: "so" }', 'JSON working content OK');

my $text = $db->find_one($text_p, { working => 1 });
is($text->{_path}, $text_p, 'Text article loaded OK');

# get the root collection
my $root = $db->get_collection;
is($root->path, '/', 'Root collection received OK');

# create a new document
my $doc_p = $root->insert('about', { subject => 'About Giddy', text => '<p>This is stupid</p>', date => '12-12-12T12:15:56+03:00' });
is($doc_p, '/about', 'Document created OK');
ok(-d File::Spec->catdir($tmpdir, 'about'), 'Document has a directory in the filesystem');
ok(-e File::Spec->catdir($tmpdir, 'about', 'attributes.yaml'), 'Document has an attributes.yaml file');

# add a fake binary file to the document
open(FILE, ">$tmpdir/about/binary");
print FILE "ASDF";
close FILE;

# commit the changes
$db->mark('about/binary');
$db->commit( "Testing another commit" );

# now find the document
my $doc = $root->find_one('about', { working => 1 });
ok($doc, 'Document now found');
is($doc->{'subject'}, 'About Giddy', 'Document loaded OK');
is($doc->{'binary'}, '/about/binary', 'Document has binary reference OK');

# search for some stuff
my $c2 = $db->find('/collection/index.html', { working => 1 });
is($c2->count, 1, 'Article found OK');

# grep for some stuff
my $g0 = $coll->grep_one('how', { working => 1 });
ok($g0, 'Found something when grepping for "how" in collection');
is($g0->{_path}, '/collection/index.json', 'Found index.json when grepping for "how" in collection');

# drop the collection
$coll->drop;
ok(!-e File::Spec->catdir($tmpdir, 'collection'), 'Collection dropped OK');

# try to drop the root collection (should fail)
eval { $root->drop; };
ok($@ && $@ =~ m/You cannot drop the root collection/, 'Root collection cannot be dropped');

# try to load the about article as a collection (should fail)
eval { $db->get_collection('about'); };
ok($@ && $@ =~ m/The collection path exists in the database as a document directory/, "Can't load a document as a collection");

# create some documents
$root->insert('one', { subject => 'Lorem Ipsum', text => 'Dolor Sit Amet', regex => qr/^asdf$/ });
$root->insert('two', { title => 'Adventureland', starring => ['Jesse Eisenberg', 'Kristen Stewart'], year => 2009, imdb_score => 7.1 });
$root->insert('three', { subject => '2009 Movies', text => "I don't know, there were many." });
$root->insert('four', { title => 'Zombieland', starring => ['Woody Harrelson', 'Jesse Eisenberg', 'Emma Stone'], year => 2009, imdb_score => 7.8 });
$root->insert('five', { title => 'Superbad', starring => ['Jonah Hill', 'Michael Cera', 'Emma Stone'], year => 2007 });

# let's perform different find queries
my $f1 = $root->find({ imdb_score => { '$exists' => 1 } }, { working => 1 });
my @r1 = $f1->all;
is($f1->count, 2, 'Got 2 results as expected when searching by $exists => 1');
ok(($r1[0]->{_path} eq '/two' && $r1[1]->{_path} eq '/four') || ($r1[1]->{_path} eq '/two' && $r1[0]->{_path} eq '/four'), 'Got the correct results when searching by $exists => 1');

my $f2 = $root->find({ imdb_score => { '$exists' => 0 } }, { working => 1 });
is($f2->count, 4, 'Got 4 results as expected when searching by $exists => 0');

my $f3 = $root->find({ imdb_score => { '$gt' => 7.5 } }, { working => 1 });
is_deeply([$f3->all], [{ _path => '/four', title => 'Zombieland', starring => ['Woody Harrelson', 'Jesse Eisenberg', 'Emma Stone'], year => 2009, imdb_score => 7.8 }], 'Got the correct result when searching by $gt => 7.5');

my $f4 = $root->find({ starring => 'Jesse Eisenberg' }, { working => 1 });
my @r4 = $f4->all;
is($f4->count, 2, 'Got 2 results as expected when searching by starring => Jesse Eisenberg');
ok(($r4[0]->{_path} eq '/two' && $r4[1]->{_path} eq '/four') || ($r4[1]->{_path} eq '/two' && $r4[0]->{_path} eq '/four'), 'Got the correct results when searching by starring => Jesse Eisenberg');

my $f5 = $root->find({ subject => qr/Movies/i }, { working => 1 });
is($f5->count, 1, 'Got 1 result as expected when searching by subject => qr/Movies/i');
is(($f5->all)[0]->{_path}, '/three', 'Got the correct result when searching by subject => qr/Movies/i');

my $f6 = $root->find({ year => { '$gte' => 2009 }, starring => qr/^Kristen/ }, { working => 1 });
is($f6->count, 1, 'Got 1 result as expected when searching by year => { $gte => 2009 }, starring => qr/^Kristen/');
is(($f6->all)[0]->{_path}, '/two', 'Got the correct result when searching by year => { $gte => 2009 }, starring => qr/^Kristen/');

my $f7 = $root->find({ subject => { '$ne' => 'Lorem Ipsum' } }, { working => 1 });
my @f7 = $f7->all;
is($f7->count, 2, 'Got 2 results as expected when searching by subject => { $ne => Lorem Ipsum }');
ok(($f7[0]->{subject} eq '2009 Movies' && $f7[1]->{subject} eq 'About Giddy') || ($f7[1]->{subject} eq '2009 Movies' && $f7[0]->{subject} eq 'About Giddy'), 'Got the correct results when searching by subject => { $ne => Lorem Ipsum }');

my $f8 = $root->find({ starring => { '$size' => 3 }, year => { '$nin' => [2006 .. 2008] } }, { working => 1 });
my @f8 = $f8->all;
is($f8->count, 1, 'Got 1 result as expected when searching by starring => { $size => 3 }, year => { $nin => [2006 .. 2008] }');
is($f8[0]->{_path}, '/four', 'Got the correct result when searching by starring => { $size => 3 }, year => { $nin => [2006 .. 2008] }');

my $f9 = $root->find({ starring => { '$all' => ['Jesse Eisenberg', 'Woody Harrelson'] } }, { working => 1 });
my @f9 = $f9->all;
is($f9->count, 1, 'Got 1 result as expected when searching by starring => { $all => [Jesse Eisenberg, Woody Harrelson] }');
is($f9[0]->{title}, 'Zombieland', 'Got the correct result when searching by starring => { $all => [Jesse Eisenberg, Woody Harrelson] }');

my $f10 = $root->find({ regex => { '$type' => 11 } }, { working => 1 });
my @f10 = $f10->all;
is($f10->count, 1, 'Got 1 result as expected when searching by regex => { $type => 11 }');
is($f10[0]->{_path}, '/one', 'Got the correct result when searching by regex => { $type => 11 }');

my $f11 = $root->find({ starring => { '$type' => 4 } }, { working => 1 });
my @f11 = $f11->all;
is($f11->count, 3, 'Got 3 results as expected when searching by starring => { $type => 4 }');

# now let's try some grep searches
my $g1 = $root->grep('Emma Stone', { working => 1 });
my @g1 = $g1->all;
is($g1->count, 2, 'Got 2 results as expected when grepping by Emma Stone');
ok(($g1[0]->{_path} eq '/four' && $g1[1]->{_path} eq '/five') || ($g1[1]->{_path} eq '/four' && $g1[0]->{_path} eq '/five'), 'Got the correct results when grepping by Emma Stone');

my $g2 = $root->grep(['Michael Cera', 'Woody Harrelson'], { 'or' => 1, 'working' => 1 });
my @g2 = $g2->all;
is($g2->count, 2, 'Got 2 results as expected when grepping by Michael Cera or Woody Harrelson');
ok(($g2[0]->{_path} eq '/four' && $g2[1]->{_path} eq '/five') || ($g2[1]->{_path} eq '/four' && $g2[0]->{_path} eq '/five'), 'Got the correct results when grepping by Michael Cera or Woody Harrelson');

my $g3 = $root->grep(['Jesse Eisenberg', 'Woody Harrelson'], { working => 1 });
my @g3 = $g3->all;
is($g3->count, 1, 'Got 1 result as expected when grepping by Michael Cera and Woody Harrelson');
is($g3[0]->{_path}, '/four', 'Got the correct result when grepping by Michael Cera and Woody Harrelson');

my $g4 = $root->grep('', { working => 1 });
is($g4->count, 6, 'Got all documents in collection when grepping by nothing');

done_testing();
