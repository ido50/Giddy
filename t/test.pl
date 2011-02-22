#!/usr/bin/perl -w

use lib '/home/ido/git/Giddy/lib';
use warnings;
use strict;
use Giddy;

# create a new Giddy repository
my $g = Giddy->new;

my $db = $g->get_database('/tmp/giddy-test');
my $coll = $db->get_collection('/collection');

# create a new file
my $html_p = $coll->insert_article('index.html', 'whatever the fuck ever', { user => 'ido50', date => '12-12-12T12:12:12+03:00' });
my $json_p = $coll->insert_article('index.json', '{ how: "so" }');
my $text_p = $coll->insert_article('asdf.txt', 'asdf', { asdf => 'AsDf' });

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
