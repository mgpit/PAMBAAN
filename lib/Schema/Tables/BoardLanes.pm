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

package Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardLanes;
use strict;

our $VERSION = '0.2';

use base qw(Exporter);
our @EXPORT = qw(
);

use Data::Dumper;

use constant TABLENAME => "pambaan_board_lanes";
use constant TRUE=>1;
use constant FALSE=>0;

sub tablename {
    return TABLENAME;
}

sub ddl {
    return {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,                
            },
            sortkey => {
                TYPE => 'INT3',
                NOTNULL => 1,
                DEFAULT => 10,
            },            
            name => {
                TYPE => 'varchar(127)',
                NOTNULL => 1,
            },
            description => {
                TYPE => 'LONGTEXT',
                NOTNULL => 0,
            },
            ### the following two columns shour REFERENCE namedqueries( userid, name )
            namedquery_name => {
                TYPE => 'varchar(127)',
                NOTNULL => 0,
            },
            namedquery_sharer_id => {
                TYPE => 'INT3',
                NOTNULL => 0,
            },            
            board_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => { 
                    TABLE => 'pambaan_boards',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },                
            },
            color => {
                TYPE => 'varchar(127)',
                NOTNULL => 0,     
            },            
        ],
    };
}

sub do_schema_000200 {

    my $dbh = Bugzilla->dbh;
    my $column_info;

    #$column_info = $dbh->bz_column_info( tablename(), 'wip_warning_threshold' );
    $dbh->bz_add_column( tablename(), 'wip_warning_threshold', { TYPE=>'INT2', NOTNULL=>0 } );
    
    #$column_info = $dbh->bz_column_info( tablename(), 'wip_overload_threshold' );
    $dbh->bz_add_column( tablename(), 'wip_overload_threshold', { TYPE=>'INT2', NOTNULL=>0 } );
    

    #$column_info = $dbh->bz_column_info( tablename(), 'space_occupied' );
    $dbh->bz_add_column( tablename(), 'space_occupied', { TYPE=>'INT2', NOTNULL=>0 } );

    
}

sub do_schema_000500 {
    my $dbh = Bugzilla->dbh;
    
    $dbh->bz_add_column( tablename(), 'card_show_asignee',      { TYPE=>'BOOLEAN', NOTNULL=>1, DEFAULT=>'TRUE' } );
    $dbh->bz_add_column( tablename(), 'card_show_importance',   { TYPE=>'BOOLEAN', NOTNULL=>1, DEFAULT=>'TRUE' } );
    $dbh->bz_add_column( tablename(), 'card_show_product',      { TYPE=>'BOOLEAN', NOTNULL=>1, DEFAULT=>'TRUE' } );
    $dbh->bz_add_column( tablename(), 'card_show_bug_status',   { TYPE=>'BOOLEAN', NOTNULL=>1, DEFAULT=>'TRUE' } );
    $dbh->bz_add_column( tablename(), 'card_show_timetracking', { TYPE=>'BOOLEAN', NOTNULL=>1, DEFAULT=>'TRUE' } );
}


sub do_schema_000601 {
    my $dbh = Bugzilla->dbh;
    
    $dbh->bz_add_column( tablename(), 'restrict_to_assignee_currusr', { TYPE=>'CHAR', NOTNULL=>0 } );    
}

1;

__END__



=head1 NAME

Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardLanes.

The Schema definitions for the C<pambaan_lanes> table.
=cut
