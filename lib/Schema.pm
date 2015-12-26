# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the PAMBAAN Bugzilla Extension.
#
# The Initial Developer of the Original Code is YOUR NAME
# Portions created by the Initial Developer are Copyright (C) 2015 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Marco Pauls <info@mgp-it.de>

package Bugzilla::Extension::PAMBAAN::Schema;
use strict;

our $VERSION="0.2";

use base qw(Exporter);
our @EXPORT = qw(
    pambaan_schema_init
    pambaan_do_schema_updates
);

use constant DDLPACKAGE=>'Bugzilla::Extension::PAMBAAN::Schema::Tables::';

use Data::Dumper;

use Bugzilla::Extension::PAMBAAN::Schema::Tables::Boards;
use Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardLanes;
use Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardsGroupMap;

use Bugzilla::Extension::PAMBAAN::Board;
use Bugzilla::Extension::PAMBAAN::Lane;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error qw( ThrowUserError );
use Bugzilla::Group;
use Bugzilla::Search;
use Bugzilla::Search::Saved;

use constant IN_COMMAND_LINE => (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) ? 1 : 0;


#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Data Definition               |
#                                                                        \______________________________/
#

sub initialize_pambaan_data {
    print "\n\nInitialzing PAMBAAN data ...\n" if IN_COMMAND_LINE;

    my $defaultboard = Bugzilla::Extension::PAMBAAN::Board::DEFAULTBOARD;
    my $user_one = new Bugzilla::User( 1 );
    my $pambaan_group = new Bugzilla::Group( {name=>"pambaan"} );
    my $canquery = $user_one && $pambaan_group;
    
    Bugzilla->set_user( $user_one ) if $canquery;
    
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    my $board = new Bugzilla::Extension::PAMBAAN::Board( { name => $defaultboard->{name} } );
    
    if ( !$board ) { 
        $board = Bugzilla::Extension::PAMBAAN::Board->create( $defaultboard );
        print "\t", "Created Default Board ", $board->name(), "\n" if IN_COMMAND_LINE;
    } 

    ### put this sub into a variable to avoid the Variable "..." will not stay shared at ...
    ### fun with lexical scoping ...
    my $buildlane = sub {
            my $params = shift;
            
            my $search = delete $params->{search};
            
            if ( $search && $canquery ) {
                
                my $saved_search = new Bugzilla::Search::Saved( { name=>$search->{name}, user=>$user_one } );

                if ( !$saved_search ) {
                    $saved_search = Bugzilla::Search::Saved->create( { name=>$search->{name}, query=>$search->{query} } );
                    print "\t", "Created Saved Search ", $saved_search->name(), "\n" if IN_COMMAND_LINE;
                }
                    
                ### print __PACKAGE__, "::buildlane ", Dumper( $saved_search ), "\n" if IN_COMMAND_LINE;
                
                $dbh->do( 'DELETE FROM namedquery_group_map WHERE namedquery_id = ?', undef, $saved_search->id() );
                $dbh->do( 'INSERT INTO namedquery_group_map( namedquery_id, group_id ) VALUES( ?, ? )', undef, $saved_search->id(), $pambaan_group->id() );
                
                $params->{namedquery_name} = $saved_search->name();
                $params->{namedquery_sharer_id} = $user_one->id();
                
            }
            
            my $lane = new Bugzilla::Extension::PAMBAAN::Lane( $params ); # contains board or board_id and name ...
            my $lanecreated = !$lane;
            $lane = Bugzilla::Extension::PAMBAAN::Lane->create( $params ) unless $lane;
            
            if ( $lanecreated ) {
                print "\t", "Created Lane ", $lane->name(), "\n" if IN_COMMAND_LINE;
                print "\t\t", "!!! Could not create Saved Search for Lane ", $lane->name(), ": No User with id 1 (one)!", "\n" if !$user_one && IN_COMMAND_LINE;
                print "\t\t", "!!! Could not create Saved Search for Lane ", $lane->name(), ": No pambaan group!", "\n" if !$pambaan_group && IN_COMMAND_LINE;
            }
            return $lane;
    }; ### buildlane
    
    
    my $lane1 = $buildlane->( { board=>$board, sortkey=>10, name=>"Backlog"     , color => ".red"    , description=> "Bug Backlog. Yet to be confirmed.",
                              , search=>{name=>'Find UNCONFIRMED', query=>'bug_status=UNCONFIRMED'}
                            } );
    my $lane2 = $buildlane->( { board=>$board, sortkey=>20, name=>"Ready"       , color => ".orange" , description=> "Bugs ready for work.",               
                              , search=>{name=>'Find CONFIRMED', query=>'bug_status=CONFIRMED'}
                            } );
    my $lane3 = $buildlane->( { board=>$board, sortkey=>30, name=>"In Progress" , color => ".blue"   , description=> "Bugs being worked on.", space_occupied=> 2
                              , search=>{name=>'Find IN PROGRESS', query=>'bug_status=IN_PROGRESS'}
                            } );
    my $lane4 = $buildlane->( { board=>$board, sortkey=>40, name=>"Done"        , color => ".green"  , description=> "Bugs finished.",
                              , search=>{name=>'Find RESOLVED or VERIFIED', query=>'bug_status=RESOLVED&bug_status=VERIFIED'}                    
                            } );

    $dbh->bz_commit_transaction();

}

sub initialize_bugzilla_data {
    print "\n\nInitialzing *additional* Bugzilla data ...\n" if IN_COMMAND_LINE;

    #
    # Create the pambaan group.
    # Named Queries shared with this group will be available for being selected
    # as population query for a board lane.
    #    
    my $definition = { name=> 'pambaan',
                       description => 'The PAMBAAN Group',
                       isbuggroup => 0,
                       isactive => 1,
                       silently => 0,
                     };
    
    my $exists = new Bugzilla::Group({ name => $definition->{name} });
    if (!$exists) {
        my $created = Bugzilla::Group->create($definition);
    }
}

sub initialize_data {
    initialize_pambaan_data;
    initialize_bugzilla_data;
}

#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Scheme Definition             |
#                                                                        \______________________________/
#

sub pkn {
    my $name = shift;
    return DDLPACKAGE . $name;
}

sub ___do_cleanup {

    my $dbh = Bugzilla->dbh;

    $dbh->bz_drop_table( pkn( "BoardLanes")->tablename() );
    $dbh->bz_drop_table( pkn( "Boards")->tablename() );
    
}

sub add_fields_to_bugs {
    # print "\nAbout to add new fields to bugs ...\n" if IN_COMMAND_LINE;
}

sub add_fields_to_other_entities {
    # print "\n\nAdding new fields to other entities ...\n" if IN_COMMAND_LINE;
}


sub schema_version_000200 {
    pkn('BoardLanes')->do_schema_000200;
}

sub schema_version_000500 {
    pkn('BoardLanes')->do_schema_000500;
}

sub schema_version_000600 {
    pkn('Boards')->do_schema_000600;
}

sub schema_version_000601 {
    pkn('Boards')->do_schema_000601;
    pkn('BoardLanes')->do_schema_000601;
}

sub add_fields_to_pambaan {
    print "\n\nAdding new fields to PAMBAAN entities ...\n" if IN_COMMAND_LINE;
    schema_version_000200;
    schema_version_000500;
    schema_version_000600;
    schema_version_000601;    
}


sub pambaan_do_schema_updates {
    ### ___do_cleanup;
    ### return;    
    add_fields_to_bugs;
    add_fields_to_other_entities;
    add_fields_to_pambaan;
    initialize_data;
}

sub addDefinition {
    ### return;
    my ( $schema, $tableDefinitionPackageName ) = @_;
    print "\n", scalar localtime(), " Pushing Definition for Table $tableDefinitionPackageName to bugs database ...", "\n" if IN_COMMAND_LINE;
    my $pkg = pkn( $tableDefinitionPackageName );
    $schema -> {$pkg->tablename() } = $pkg->ddl();
}

sub pambaan_schema_init {
    my $schema = shift;
    addDefinition( $schema, "Boards" );
    addDefinition( $schema, "BoardLanes" );
    addDefinition( $schema, "BoardsGroupMap" );
}


1;

__END__


=head1 NAME

Bugzilla::Extension::PAMBAAN::Schema.

The Schema definitions for SimpleKanban.
=cut
