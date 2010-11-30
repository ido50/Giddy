#!/usr/bin/perl -w

use lib '/home/ido/git/Giddy/lib';
use warnings;
use strict;
use Giddy;

# create a new Giddy repository
my $g = Giddy->create('/tmp/giddy-test');

# create a new Giddy collection
my $coll = $g->new_collection('/collection');

# create a new file
my $file = $coll->new_file('index.html', 'whatever the fuck ever');
$coll->new_file('index.json', '{ how: "so" }');
$coll->new_file('asdf.txt', 'asdf');

print "Working content: ", $file->working_content, "\n";

# create a new document
$coll->new_document('about', { 'subject.txt' => 'About Giddy', 'text.html' => '<p>This is stupid</p>' });

# commit the changes
$g->commit( "Testing a commit" );

print "Saved content: ", $file->content, "\n";

print "Searching for /collection/index.html\n";
my $cursor = $g->find('/collection/index.html');
print "Found ".$cursor->count." results:\n";
foreach ($cursor->all) {
	print $_->id, " => ", $_->content, "\n";
}

print "Searching for /collection/about\n";
my $c2 = $g->find('/collection/about');
print "Found ".$c2->count." results:\n";
foreach ($c2->all) {
	print $_->name, ': ', join(', ', $_->attrs), "\n";
}
