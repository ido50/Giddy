#!perl

use warnings;
use strict;
use utf8;

use File::Temp qw/tempdir/;
use Giddy;
use Test::More;
use Test::Git;
use Try::Tiny;

has_git();

plan tests => 93;

my $tmpdir = tempdir(CLEANUP => 1);
diag("Gonna use $tmpdir for the temporary database directory");

# create a new Giddy object
my $g = Giddy->new;
ok($g, 'Got a proper Giddy object');

# create a Giddy database
my $db = $g->get_database($tmpdir);
is(ref($db->_repo), 'Git::Repository', 'Created a new Giddy database');

# create a Giddy collection
my $coll = $db->get_collection('collection');
is($coll->path, 'collection', 'Created a new Giddy collection');
ok(-d $tmpdir.'/collection', 'New collection has a directory in the filesystem');

# create some articles
my $html_n = $coll->insert('index.html', { _body => '<h1>Giddy</h1>', user => 'gitguy', date => '12-12-12T12:12:12+03:00' });
is($html_n, 'index.html', 'Created an HTML article');

my $json_n = $coll->insert('index.json', { _body => '{ how: "so" }' });
ok(-e $tmpdir.'/collection/index.json', 'Created a JSON article');

my $text_n = $coll->insert('asdf.txt', { _body => 'asdf', asdf => 'AsDf' });
is($text_n, 'asdf.txt', 'Create a text article');

# commit the changes
$db->commit( "Testing a commit" );

# take a look at the contents of the articles
my $html = $db->find_one("collection/$html_n");
ok($html, 'Found HTML document');
is($html->{_body}, '<h1>Giddy</h1>', 'HTML content OK');
is($html->{user}, 'gitguy', 'HTML attributes OK');

my $json = $db->find_one("collection/$json_n");
ok($json, 'Found JSON document');
is($json->{_body}, '{ how: "so" }', 'JSON content OK');

my $text = $coll->find_one($text_n);
ok($text, 'Found text document');
is($text->{_name}, 'asdf.txt', 'Text document loaded OK');

# get the root collection
my $root = $db->get_collection;
is($root->path, '', 'Root collection received OK');

# create a new document
my $doc_n = $root->insert('about', { subject => 'About Giddy', text => '<p>This is stupid</p>', date => '12-12-12T12:15:56+03:00' });
is($doc_n, 'about', 'Document created OK');
ok(-d $tmpdir.'/about', 'Document has a directory in the filesystem');
ok(-e $tmpdir.'/about/attributes.yaml', 'Document has an attributes.yaml file');

# search for the document before commiting
my $c1 = $db->find($doc_n);
is($c1->count, 0, 'Document cannot be found before commiting');

# add a fake binary file to the document
open(FILE, ">$tmpdir/about/binary");
print FILE "ASDF";
close FILE;

# commit the changes
$db->stage('about/binary');
$db->commit( "Testing another commit" );

# now find the document
my $doc = $root->find_one('about');
ok($doc, 'Document now found');
is($doc->{subject}, 'About Giddy', 'Document loaded OK');
is($doc->{binary}, 'about/binary', 'Document has binary reference OK');

# search for some stuff
my $c2 = $db->find('collection/index.html');
is($c2->count, 1, 'Article found OK');

# grep for some stuff
my $g0 = $coll->grep_one('how');
ok($g0, 'Found something when grepping for "how" in collection');
is($g0->{_name}, 'index.json', 'Found index.json when grepping for "how" in collection');

# let's try to load the collection as a static directory and make sure it fails
my $failed0 = try { $root->get_static_dir('collection') } catch { 'failed' };
is($failed0, 'failed', "Can't load collection as a static-file directory");

# let's check child collection getting and parent collection getting
my $child_coll = $root->get_collection('collection');
ok($child_coll, 'Got a child collection object from root collection');
is($child_coll->path, 'collection', 'Got the correct child collection object from the root collection');
my $parent_coll = $child_coll->get_parent;
ok($parent_coll, 'Got the parent collection from a child collection');
is($parent_coll->path, '', 'Got the correct parent collection from a child collection');
ok(!$root->get_parent, "Can't get the parent of the root collection since such a parent doesn't exist");

# drop the collection
$coll->drop;
ok(!-e $tmpdir.'/collection', 'Collection dropped OK');

$db->commit('Dropped a collection');

# try to drop the root collection (should fail)
my $dropped = try { $root->drop } catch { 'failed' };
is($dropped, 'failed', 'Root collection cannot be dropped');

# create some documents
$root->insert('one', { subject => 'Lorem Ipsum', text => 'Dolor Sit Amet', regex => qr/^asdf$/ });
$root->insert('two', { title => 'Adventureland', starring => ['Jesse Eisenberg', 'Kristen Stewart'], year => 2009, imdb_score => 7.1 });
$root->insert('three', { subject => '2009 Movies', text => "I don't know, there were many." });
$root->insert('four', { title => 'Zombieland', starring => ['Woody Harrelson', 'Jesse Eisenberg', 'Emma Stone'], year => 2009, imdb_score => 7.8 });
$root->insert('five', { title => 'Superbad', starring => ['Jonah Hill', 'Michael Cera', 'Emma Stone'], year => 2007, utf8 => 'עידו פרלמוטר' });

$db->commit('created some documents');

# let's perform different find queries
my $f0 = $root->find_one({ utf8 => { '$exists' => 1 } });
ok($f0, 'Found a document that has the utf8 attribute');
is($f0->{_name}, 'five', 'Found the correct document with a utf8 attribute');
is($f0->{utf8}, 'עידו פרלמוטר', 'UTF-8 text properly decoded');

my $f1 = $root->find({ imdb_score => { '$exists' => 1 } });
my @r1 = $f1->all;
is($f1->count, 2, 'Got 2 results as expected when searching by imdb_score => { $exists => 1 }');
ok(($r1[0]->{_name} eq 'two' && $r1[1]->{_name} eq 'four') || ($r1[1]->{_name} eq 'two' && $r1[0]->{_name} eq 'four'), 'Got the correct results when searching by $exists => 1');

my $f2 = $root->find({ imdb_score => { '$exists' => 0 } });
is($f2->count, 4, 'Got 4 results as expected when searching by imdb_score => { $exists => 0 }');

my $f3 = $root->find({ imdb_score => { '$gt' => 7.5 } });
is_deeply([$f3->all], [{ _name => 'four', title => 'Zombieland', starring => ['Woody Harrelson', 'Jesse Eisenberg', 'Emma Stone'], year => 2009, imdb_score => 7.8 }], 'Got the correct result when searching by $gt => 7.5');

my $f4 = $root->find({ starring => 'Jesse Eisenberg' });
my @r4 = $f4->all;
is($f4->count, 2, 'Got 2 results as expected when searching by starring => Jesse Eisenberg');
ok(($r4[0]->{_name} eq 'two' && $r4[1]->{_name} eq 'four') || ($r4[1]->{_name} eq 'two' && $r4[0]->{_name} eq 'four'), 'Got the correct results when searching by starring => Jesse Eisenberg');

my $f5 = $root->find({ subject => qr/Movies/i });
is($f5->count, 1, 'Got 1 result as expected when searching by subject => qr/Movies/i');
is(($f5->all)[0]->{_name}, 'three', 'Got the correct result when searching by subject => qr/Movies/i');

my $f6 = $root->find({ year => { '$gte' => 2009 }, starring => qr/^Kristen/ });
is($f6->count, 1, 'Got 1 result as expected when searching by year => { $gte => 2009 }, starring => qr/^Kristen/');
is(($f6->all)[0]->{_name}, 'two', 'Got the correct result when searching by year => { $gte => 2009 }, starring => qr/^Kristen/');

my $f7 = $root->find({ subject => { '$ne' => 'Lorem Ipsum' } });
my @f7 = $f7->all;
is($f7->count, 2, 'Got 2 results as expected when searching by subject => { $ne => Lorem Ipsum }');
ok(($f7[0]->{subject} eq '2009 Movies' && $f7[1]->{subject} eq 'About Giddy') || ($f7[1]->{subject} eq '2009 Movies' && $f7[0]->{subject} eq 'About Giddy'), 'Got the correct results when searching by subject => { $ne => Lorem Ipsum }');

my $f8 = $root->find({ starring => { '$size' => 3 }, year => { '$nin' => [2006 .. 2008] } });
my @f8 = $f8->all;
is($f8->count, 1, 'Got 1 result as expected when searching by starring => { $size => 3 }, year => { $nin => [2006 .. 2008] }');
is($f8[0]->{_name}, 'four', 'Got the correct result when searching by starring => { $size => 3 }, year => { $nin => [2006 .. 2008] }');

my $f9 = $root->find({ starring => { '$all' => ['Jesse Eisenberg', 'Woody Harrelson'] } });
my @f9 = $f9->all;
is($f9->count, 1, 'Got 1 result as expected when searching by starring => { $all => [Jesse Eisenberg, Woody Harrelson] }');
is($f9[0]->{title}, 'Zombieland', 'Got the correct result when searching by starring => { $all => [Jesse Eisenberg, Woody Harrelson] }');

my $f10 = $root->find({ regex => { '$type' => 'regex' } });
my @f10 = $f10->all;
is($f10->count, 1, 'Got 1 result as expected when searching by regex => { $type => regex }');
is($f10[0]->{_name}, 'one', 'Got the correct result when searching by regex => { $type => regex }');

my $f11 = $root->find({ starring => { '$type' => 'array' } });
my @f11 = $f11->all;
is($f11->count, 3, 'Got 3 results as expected when searching by starring => { $type => array }');

# now let's try some grep searches
my $g1 = $root->grep('Emma Stone');
my @g1 = $g1->all;
is($g1->count, 2, 'Got 2 results as expected when grepping by Emma Stone');
ok(($g1[0]->{_name} eq 'four' && $g1[1]->{_name} eq 'five') || ($g1[1]->{_name} eq 'four' && $g1[0]->{_name} eq 'five'), 'Got the correct results when grepping by Emma Stone');

my $g2 = $root->grep(['Michael Cera', 'Woody Harrelson'], { 'or' => 1 });
my @g2 = $g2->all;
is($g2->count, 2, 'Got 2 results as expected when grepping by Michael Cera or Woody Harrelson');
ok(($g2[0]->{_name} eq 'four' && $g2[1]->{_name} eq 'five') || ($g2[1]->{_name} eq 'four' && $g2[0]->{_name} eq 'five'), 'Got the correct results when grepping by Michael Cera or Woody Harrelson');

my $g3 = $root->grep(['Jesse Eisenberg', 'Woody Harrelson']);
my @g3 = $g3->all;
is($g3->count, 1, 'Got 1 result as expected when grepping by Michael Cera and Woody Harrelson');
is($g3[0]->{_name}, 'four', 'Got the correct result when grepping by Michael Cera and Woody Harrelson');

my $g4 = $root->grep;
is($g4->count, 6, 'Got all documents in collection when grepping by nothing');

# search for some documents by _name
my $f12 = $root->find({ _name => 'one' });
is($f12->count, 1, 'Found 1 document as expected when searching by _name => one');
is($f12->next->{_name}, 'one', 'Found the correct document when searching by name => one');

my $f13 = $root->find({ _name => qr/^t/, starring => { '$exists' => 0 } });
is($f13->count, 1, 'Found 1 document as expected when searching by _name => qr/^t/, starring => { $exists => 0 }');
is($f13->first->{_name}, 'three', 'Found the correct document when searching by _name => qr/^t/, starring => { $exists => 0 }');

my $f14 = $root->find({ _name => { '$ne' => 'two' } });
is($f14->count, 5, 'Found 5 documents as expected when searching by _name => { $ne => two }');

# let's sort some stuff
my $f15 = $root->find->sort([ 'imdb_score' => -1, '_name' => 1 ]);
is_deeply([$f15->_documents->Keys], ['four', 'two', 'about', 'five', 'one', 'three'], 'Documents properly sorted in f15');

my $f16 = $root->find->sort([ 'imdb_score' => 1, '_name' => -1 ]);
is_deeply([$f16->_documents->Keys], ['two', 'four', 'three', 'one', 'five', 'about'], 'Documents properly sorted in f16');

my $f17 = $root->find->sort(Tie::IxHash->new('year' => -1, 'title' => 1));
is_deeply([$f17->_documents->Keys], ['two', 'four', 'five', 'about', 'one', 'three'], 'Documents properly sorted in f17');

# try to update a document
my $u1 = $root->update({ starring => 'Jesse Eisenberg' }, { '$pull' => { starring => 'Jesse Eisenberg' }, '$push' => { starring => 'Jesse Fakerberg' } }, { multiple => 1 });
is($u1->{n}, 2, 'u1 updated 2 documents as expected');
ok(($u1->{docs}->[0] eq 'two' && $u1->{docs}->[1] eq 'four') || ($u1->{docs}->[1] eq 'two' && $u1->{docs}->[0] eq 'four'), 'u1 updated the correct documents');

my $u2 = $root->update({ _name => 'about' }, { '$set' => { updated => time() } });
is($u2->{n}, 1, 'u2 updated 1 document as expected');
is($u2->{docs}->[0], 'about', 'u2 updated the correct document');

my $u3 = $root->update({ imdb_score => { '$exists' => 1 } }, { '$rename' => { year => 'release_year' }, '$inc' => { imdb_score => -10 } }, { multiple => 1 });
is($u3->{n}, 2, 'u3 updated 2 documents as expected');

$db->commit('updated some documents');

# let's test query chaining
my $f18 = $root->find->find({ starring => { '$exists' => 1 } })->find({ starring => { '$size' => 2 } });
is($f18->count, 1, 'Got 1 result as expected for f18 (chain queries)');
is_deeply($f18->first->{starring}, ['Jesse Eisenberg', 'Kristen Stewart'], 'Got the correct result for f18 (chain queries)');

my $g5 = $root->find({ imdb_score => { '$exists' => 1 } })->grep('Emma Stone');
is($g5->count, 1, 'Got 1 result as expected for g5 (chain queries)');
is($g5->first->{_name}, 'four', 'Got the correct result for g5 (chain queries)');

# let's try to load some objects by the wrong type and make sure Giddy croaks
# 1. try to load the about article as a collection
my $failed1 = try { $db->get_collection('about') } catch { 'failed' };
is($failed1, 'failed', "Can't load a document as a collection");
# 2. try to load the about article as a static directory
my $failed2 = try { $root->get_static_dir('about') } catch { 'failed' };
is($failed2, 'failed', "Can't load a document as a static-file directory");

# let's remove some documents
$root->remove('about');
ok(!-e $tmpdir.'/about', 'about document removed OK');
$root->remove({ _name => qr/^t/ }, { multiple => 1 });
ok(!-e $tmpdir.'/two' && !-e $tmpdir.'/three', 'two and three documents removed OK');
# We should still be able to find the files
my $two = $root->find_one('two');
is($two->{release_year}, 2009, 'two is still there since we haven\'t commited yet');
$db->commit('removed some documents');
# now we shouldn't be able to find two
$two = $root->find_one('two');
ok(!defined $two, 'two not there anymore since we have commited its removal');

# let's revert the latest commit and see if the documents are magically returned
$db->revert;
$two = $root->find_one('two');
ok($two->{_name} eq 'two', 'two is back again');

# let's undo the revert (yeah, i'm crazy like that)
$db->undo;
$two = $root->find_one('two');
ok(!defined $two, 'two not there yet again');

# let's play around with static-file directories
my $stat = $root->get_static_dir('pics');
ok($stat, 'Got a static-file directory object');
is($stat->path, 'pics', 'Static dir obj has correct path');
ok(-e $db->_repo->work_tree.'/'.$stat->path.'/.static', '.static file exists');

# let's get that static dir again and see we don't fail for some reason (i.e. from
# tryin to create the directory again)
$stat = $root->get_static_dir('pics');
ok($stat, 'Got the same static-file directory object again');

# let's create some static files
my $fh1 = $stat->open_text_file('README');
$fh1->print("Shot through the heart, and you're to blame, darlin' you give love a bad name.");
$fh1->close;
ok(-e $db->_repo->work_tree.'/pics/README', 'Static file created OK');

$db->stage('pics/');
$db->commit("Created a README file under pics");

my $readme = $stat->read_file('README');
is($readme, "Shot through the heart, and you're to blame, darlin' you give love a bad name.", 'Static file read OK');

done_testing();
