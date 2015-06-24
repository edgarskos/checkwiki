#! /usr/bin/env perl

###########################################################################
##
##          FILE: dump_dispatcher.pl 
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg
##
##   DESCRIPTION: Checks for new dump files from all languages.
##                If new dump file is found, send checkwiki.pl proccess
##                to the queue.
##
##        AUTHOR: Bryan White
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;
use utf8;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

our @Projects;
our @Last_Dump;

#Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;
our $dbh;

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Options = (
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
);

GetOptions(
    'c=s' => sub {
        my $f = IO::File->new( $_[1], '<' )
          or die( "Can't open " . $_[1] . "\n" );
        local ($/);
        my $s = <$f>;
        $f->close();
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    }
);

#--------------------

open_db();
get_projects();

my $count = 0;
my $queued_count = 0;
foreach (@Projects) {

    # Due to WMFlabs incompetence, below projects are very late showing up
    if ( $_ ne 'enwiki' and $_ ne 'frwiki' and $_ ne 'commonswiki' and $_ ne 'ruwiktionary') {
        my $lastDump = $Last_Dump[$count];
        my ( $latestDumpDate, $latestDumpFilename ) = FindLatestDump($_);

        print "PROJECT:" . $_ . "  LASTDUMP" . $lastDump . "  LATEST:" . $latestDumpDate . "\n";
        if ( $queued_count < 10 ) {    # Queue max is 16 jobs at one time.
            if ( !defined($lastDump) || $lastDump ne $latestDumpDate ) {
                queueUp( $_, $latestDumpDate, $latestDumpFilename );
                $queued_count++;
            }
        }
    }
    $count++;

}

close_db();

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            mysql_enable_utf8 => 1,
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {

    my $sth = $dbh->prepare('SELECT Project, Last_Dump FROM cw_overview;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my ( $project_sql, $last_dump_sql );
    $sth->bind_col( 1, \$project_sql );
    $sth->bind_col( 2, \$last_dump_sql );
    while ( $sth->fetchrow_arrayref ) {
        push( @Projects,  $project_sql );
        push( @Last_Dump, $last_dump_sql );
    }

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub FindLatestDump {
    my ($project) = @_;

    my @Filenames =
      </public/dumps/public/$project/*/$project-*-pages-articles.xml.bz2>;
    if ( !@Filenames ) {
        return undef;
    }

    if ( $Filenames[ -1 ] !~
m!/public/dumps/public/\Q$project\E/((\d{4})(\d{2})(\d{2}))*/\Q$project\E-\1-pages-articles.xml.bz2!
      )
    {
        die( "Couldn't parse filename '" . $Filenames[ -1 ] . "'\n" );
    }

    return ( $2 . '-' . $3 . '-' . $4, $Filenames[ -1 ] );
}

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $lang, $date, $file ) = @_;

    system(
        '/usr/bin/jsub',
        '-mem', '512m',
        '-N', $lang . '-munch',
        '-once',
        '-j', 'y',
        '-o', '/data/project/checkwiki/var/log',
        '/data/project/checkwiki/bin/checkwiki.pl',
        '-c', '/data/project/checkwiki/checkwiki.cfg',
        '--project', $lang,
        '--tt',
        '--dumpfile', $file,
    );

    print "/usr/bin/jsub\n";
    print "-mem, 512m\n";
    print '-N, ' . $lang . "-munch\n";
    print "-once\n";
    print "-j, y\n";
    print "-o, /data/project/checkwiki/var/log\n";
    print "/data/project/checkwiki/bin/checkwiki.pl\n";
    print "-c, /data/project/checkwiki/checkwiki.cfg\n";
    print '--project,' . $lang . "\n";
    print "--tt,\n";
    print '--dumpfile,' . $file . "\n\n\n";
}
