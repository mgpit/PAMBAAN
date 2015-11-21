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

package Bugzilla::Extension::PAMBAAN::Schema::Tables::SkillValues;
use strict;
use base qw(Exporter);

our @EXPORT = qw(
);

use Data::Dumper;

use constant TABLENAME => "pambaan_skill_values";
use constant COLUMNS => [ "id", "skillname", "sortierung" ];


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
            skillname => {
                TYPE => 'varchar(127)',
                NOTNULL => 1,
            },
            sortierung => {
                TYPE => 'INT2',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
    };
}


#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Data                          |
#                                                                        \______________________________/
#
sub definitions {
    my $tablename = TABLENAME;
    my $columns = COLUMNS;
    my @insertColumns = grep($_ ne 'id', @{ $columns } );
    return ( $tablename, \@{ $columns }, \@insertColumns );
}

sub makeStringsFrom {
    my @columns = @_;
    my $columnNames = join( ", ", @columns );
    my @ph = map( "?", @columns );
    my $placeholders = join( ", ", @ph );
    return ( $columnNames, $placeholders );
}


1;

__END__
