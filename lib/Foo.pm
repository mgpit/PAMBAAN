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

package Bugzilla::Extension::PAMBAAN::Foo;


use strict;
use base qw(Exporter);
our @EXPORT = qw(
    
);

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
  
    my $bar = shift;
  
    my $self;      
  
    if ( defined $bar ) {
        $self = {
            bar=>$bar,
        };
    } else {
        $self = {
        };
    }
    
    my $friggle = new Bugzilla::Extension::PAMBAAN::Foo::Bar( "Donut" );
    $self->{friggle} = $friggle;
        
    bless($self, $class);
    
    return $self;    
}

sub bar {
    my $self = shift;
    my $bar = shift;
    
    $self->{bar} = $bar || $self->{bar};

    return $self->{bar};
}



package Bugzilla::Extension::PAMBAAN::Foo::Bar;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
  
    my $friggle = shift;
  
    my $self;
  
    if ( defined $friggle ) {
        $self = {
            friggle => $friggle,
        };
    } else {
        $self = {
        };
    }
        
    bless($self, $class);
    
    return $self;    
}

sub friggle {
    my $self = shift;
    my $bar = shift;
    
    $self->{friggle} = $bar || $self->{friggle};

    return $self->{friggle};
}

1;
