use strict;
use warnings;

use Data::Dumper;

{
package Foo;

use strict;
use warnings;

sub new {
    my $class = shift @_;

    print "class = $class\n";

    my $self = {};

    return bless $self, $class;
}
1;
}
{
    print "-------------------------\n";
    print "Arrow test:\n";
    my $regular_foo = Foo->new();
    print Dumper($regular_foo);
    print "-------------------------\n\n";

    print "-------------------------\n";
    print "Colon test:\n";
    my $colon_foo = Foo::new();
    print Dumper($colon_foo);
    print "-------------------------\n\n";

    print "-------------------------\n";
    print "'new' test:\n";
    my $new_foo = new Foo;
    print Dumper($new_foo);
    print "-------------------------\n\n";
}
