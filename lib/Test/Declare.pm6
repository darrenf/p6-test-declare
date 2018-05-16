use v6.c;
unit class Test::Declare:ver<0.0.1>:auth<darrenf "81590+darrenf@users.noreply.github.com">;

=begin pod

=head1 NAME

Test::Declare - Declare common test scenarios as data.

=head1 SYNOPSIS

    use Test::Declare;

    use Module::Under::Test;

    declare(
        ${
            name => 'multiply',
            call => {
                class => Module::Under::Test,
                construct => \(2),
                method => 'multiply',
            },
            args => \(multiplicand => 4),
            expected => {
                return-value => 8,
            },
        },
        ${
            name => 'multiply fails',
            call => {
                class => Module::Under::Test,
                construct => \(2),
                method => 'multiply',
            },
            args => \(multiplicand => 'four'),
            expected => {
                dies => True,
            },
        },
        ${
            name => 'multiply fails',
            call => {
                class => Module::Under::Test,
                construct => \(2),
                method => 'multiply',
            },
            args => \(multiplicand => 8),
            expected => {
                return-value => roughly(&[>], 10),
            },
        },
    );

=head1 DESCRIPTION

Test::Declare is an opinionated framework for writing tests without writing (much) code.
The author viscerally hates bugs and strongly believes in the value of tests. Since most tests
are code, they are susceptible to bugs, and so this module provides a way to express a wide
variety of common testing scenarios purely in a declarative way.

=head1 USAGE

Direct usage of this module is via the exported subroutines C<declare> and, maybe, C<roughly>.

=head2 declare(${ … }, ${ … })

C<declare> takes an array of hashes describing the test scenarios and expectations. Each hash should look like this:

=item1 name

The name of the test, for developer understanding in the TAP output.

=item1 call

A hash describing the code to be called.

=item2 class

The actual concrete class - not a string representation, and not an instance either.

=item2 method

String name of the method to call.

=item2 construct

If required, a L<Capture> of the arguments to the class's C<new> method.

=item1 args

If required, a L<Capture> of the arguments to the instance's method.

=item1 expected

A hash describing the expected behaviour when the method gets called.

=item2 return-value

The return value of the method, which will be compared to the actual return value via C<eqv>.

=item2 lives/dies/throws

C<lives> and C<dies> are booleans, expressing simply whether the code should work or not. C<throws> should be an Exception type.

=item2 stdout/stderr

Strings against which the method's output/error streams are compared, using C<eqv> (i.e. not a regex).

=head2 roughly

If an exact comparison doesn't suffice for C<return-value>, you can use C<roughly> to
change the test behaviour to something more fuzzy. The syntax is:

    return-value => roughly($operator, $right-hand-side)

For example:

    # I don't know what the value is, only that it's less than 10
    return-value => roughly(&[<], 10),

C<$operator> is typically intended to be one of the builtin infix operators but any L<Sub> which takes 2 positional arguments should do.

=head1 AUTHOR

Darren Foreman <darren.s.foreman@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2018 Darren Foreman

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

use IO::Capture::Simple;
use Test;

use Test::Declare::Callable;
use Test::Declare::Expectations;
use Test::Declare::Result;

has Str $.name is required;
has %.expected is required;
has %.call is required;
has Capture $.args;
has Bool $.debug = False;

has $!callable = Test::Declare::Callable.new(|self.call);
has $!expectations = Test::Declare::Expectations.new(|self.expected);
has $!result = Test::Declare::Result.new();

method execute() {
    $!callable.args = $!args if $!args;
    diag sprintf('calling %s.%s', $!callable.class.^name, $!callable.method) if self.debug;
    try {
        CATCH {
            default {
                $!result.status = 'died';
                $!result.exception = $_;
            }
        }
        my ($stdout, $stderr, $stdin) = capture {
            $!result.return-value = $!callable.call();
        }
        $!result.streams = stdout => $stdout, stderr => $stderr, stdin => $stdin;
    }
}
method test-streams() {
    if ($!expectations.stdout) {
        ok(
            $!expectations.stdout.compare(
                $!result.streams{'stdout'}
            ),
            self.name ~ ' - stdout'
        );
    }
    if ($!expectations.stderr) {
        ok(
            $!expectations.stderr.compare(
                $!result.streams{'stderr'}
            ),
            self.name ~ ' - stderr'
        );
    }
}
method test-status() {
    if ($!expectations.lives) {
        ok(!$!result.status, self.name ~ ' lived');
    }
    else {
        if ($!expectations.dies) {
            is($!result.status, 'died', self.name ~ ' - died');
        }
        if ($!expectations.throws) {
            isa-ok(
                $!result.exception,
                $!expectations.throws,
                sprintf(
                    '%s - threw a(n) %s (actually: %s)',
                    self.name,
                    $!expectations.throws,
                    $!result.exception.^name,
                ),
            );
        }
    }
}

method test-return-value() {
    if my $rv = $!expectations.return-value {
        my $test-description = sprintf('%s - return value', self.name);
        if self.debug {
            $test-description ~= sprintf(
                ' (%s %s %s)',
                $!result.return-value.Str,
                $rv.op.name,
                $rv.rhs.Str,
            );
        }
        ok($rv.compare($!result.return-value),$test-description);
    }
    elsif $!result.return-value && self.debug {
        diag self.name ~ ' - got untested return value ->';
        diag '   ' ~ $!result.return-value;
    }
    if my $mut = $!expectations.mutates {
        ok(
            $mut.compare(|$!callable.args),
            sprintf(
                '%s - mutates',
                self.name,
            ),
        );
    }
}

sub declare(*@tests where {$_.all ~~Hash}) is export {
    plan @tests.Int;
    for @tests -> %test {
        my $td = Test::Declare.new(|%test);
        subtest $td.name => sub {
            plan $td.expected.Int;
            $td.execute();
            $td.test-streams();
            $td.test-status();
            $td.test-return-value();
        }
    }
}