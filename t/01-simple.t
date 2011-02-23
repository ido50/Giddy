#!perl -T

use warnings;
use strict;
use Test::More tests => 10;
use Giddy;

# create a new Giddy object
my $g = Giddy->new;
ok($g, 'Got a proper Giddy object');

# create a Giddy database
my $db = $g->get_database('/tmp/giddy-test');
is(ref($db->_repo), 'Git::Repository', 'Created a new Giddy database');

# create a Giddy collection
my $coll = $db->get_collection('/collection');
is($coll->path, 'collection', 'Created a new Giddy collection');
ok(-d '/tmp/giddy-test/collection', 'New collection has a directory in the filesystem');

# create some articles
my $html_p = $coll->insert_article('index.html', 'whatever the fuck ever', { user => 'ido50', date => '12-12-12T12:12:12+03:00' });
is($html_p, 'collection/index.html', 'Created an html article');

my $json_p = $coll->insert_article('index.json', '{ how: "so" }');
ok(-e '/tmp/giddy-test/collection/index.json', 'Created a json article');

my $text_p = $coll->insert_article('asdf.txt', 'asdf', { asdf => 'AsDf' });
is($text_p, 'collection/asdf.txt', 'Create a text article');

# commit the changes
$db->commit( "Testing a commit" );

my $html = $db->find_one($html_p, { working => 1 });
my $json = $db->find_one($json_p, { working => 1 });
my $text = $db->find_one($text_p, { working => 1 });

print "HTML working content: ", $html->{body}, "\n";
print "JSON working content: ", $json->{body}, "\n";
print "TEXT working content: ", $text->{body}, "\n";

# create a new document
my $doc_p = $coll->insert_document('about', { 'subject.txt' => 'About Giddy', 'text.html' => '<p>This is stupid</p>' }, { date => '12-12-12T12:15:56+03:00' });

# commit the changes
$db->commit( "Testing another commit" );

my $doc = $db->find_one($doc_p);

print "Searching for /collection/index.html\n";
my $cursor = $db->find('/collection/index.html');
print "Found ".$cursor->count." results:\n";
foreach ($cursor->all) {
	print $_->{path}, " => ", $_->{body}, "\n";
}

print "Searching for /collection/about\n";
my $c2 = $db->find('/collection/about');
print "Found ".$c2->count." results:\n";
foreach ($c2->all) {
	print $_->{path}, "\n";
}
