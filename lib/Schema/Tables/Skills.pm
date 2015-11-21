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

package Bugzilla::Extension::PAMBAAN::Schema::Tables::Skills;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
);

# This file can be loaded by your extension via 
# "use Bugzilla::Extension::PAMBAAN::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub tablename {
    return "pambaan_skills";
}

sub ddl {
    return {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,                
            },
            skillbezeichnung => {
                TYPE => 'varchar(127)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            pambaan_skillbezeichnung_idx => {
                FIELDS => ['skillbezeichnung'],
                TYPE => 'UNIQUE',
            },
        ],
    };
}



1;

__END__
