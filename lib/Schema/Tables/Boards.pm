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

package Bugzilla::Extension::PAMBAAN::Schema::Tables::Boards;
use strict;

our $VERSION = '0.2';

use base qw(Exporter);
our @EXPORT = qw(
);

use Data::Dumper;

use constant TABLENAME => "pambaan_boards";
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
            name => {
                TYPE => 'varchar(127)',
                NOTNULL => 1,
            },
            description => {
                TYPE => 'LONGTEXT',
                NOTNULL => 1,
            },
            defaultBoard => {
                TYPE => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'FALSE',
            },
        ],
        INDEXES => [
            pambaan_boards_name_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
        ],
    };
}



1;

__END__
