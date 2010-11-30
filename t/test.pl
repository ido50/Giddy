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

print $file->working_content, "\n";

# create a new document
$coll->new_document('about', { 'subject.txt' => 'About Giddy', 'text.html' => '<p>This is stupid</p>' });

# commit the changes
$g->commit( "Testing a commit" );

print $file->content, "\n";

my $cursor = $g->find('/collection/index');
print "Found ".$cursor->count." results:\n";
foreach ($cursor->all) {
	print $_->id, " => ", $_->content, "\n";
}
