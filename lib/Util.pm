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

package Bugzilla::Extension::PAMBAAN::Util;
use strict;
use base qw(Exporter);
use Data::Dumper;
our @EXPORT = qw(
    allowed_for_pambaan
);

sub allowed_for_pambaan {
    my $throwerror = shift;
    my $user = Bugzilla->user;
    my $group="pambaan";
    my $ingroup = 0;
    if ($user->id) {
        $ingroup = $user->in_group($group) ? 1 : 0;
    }
    ThrowUserError("pambaan_access_denied") if ($throwerror && !$ingroup);
    return $ingroup;
}


# This file can be loaded by your extension via 
# "use Bugzilla::Extension::PAMBAAN::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

1;
