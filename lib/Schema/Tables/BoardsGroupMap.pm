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
#   YOUR NAME <YOUR EMAIL ADDRESS>

package Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardsGroupMap;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
);

use Data::Dumper;

use constant TABLENAME => "pambaan_boards_group_map";
use constant COLUMNS => [ "board_id", "group_id" ];


sub tablename {
    return TABLENAME;
}

sub ddl {
    return {
        FIELDS => [
            board_id => { 
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => { 
                    TABLE  => 'pambaan_boards',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            group_id => { 
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => { 
                    TABLE => 'groups',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
             },
        ], 
        INDEXES => [
            pambaan_boards_group_map_idx => {
                FIELDS => [ qw( board_id group_id ) ],
                TYPE => 'UNIQUE'
            },
        ]
    };
}



1;

__END__


=head1 NAME

Bugzilla::Extension::PAMBAAN::Schema::Tables::BoardsGroupMap.

The Schema definitions for the C<pambaan_boards_group_map> table.
=cut
