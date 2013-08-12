require 'spec_helper'
require 'rosh/host/package_types/brew'


describe Rosh::Host::PackageTypes::Brew do
  let(:shell) { double 'Rosh::Host::Shell', :su? => false }

  subject do
    Rosh::Host::PackageTypes::Brew.new('thing', shell)
  end

  describe '#info' do
    let(:output) do
      <<-OUTPUT
thing: stable 2.0.21, HEAD
http://www.monkey.org/~provos/libevent/
/usr/local/Cellar/libevent/2.0.16 (48 files, 1.9M)
/usr/local/Cellar/libevent/2.0.17 (48 files, 1.8M)
/usr/local/Cellar/libevent/2.0.19 (48 files, 1.8M)
/usr/local/Cellar/libevent/2.0.20 (48 files, 1.8M)
/usr/local/Cellar/libevent/2.0.21 (48 files, 1.8M) *
https://github.com/mxcl/homebrew/commits/master/Library/Formula/libevent.rb
==> Options
--enable-manpages
	Install the libevent manpages (requires doxygen)
--universal
	Build a universal binary
      OUTPUT
    end

    before do
      expect(shell).to receive(:exec).with('brew info thing') { output }
    end

    it 'parses each field and value to a Hash' do
      expect(subject.info).to eq({
        package: 'thing',
        spec: 'stable',
        version: '2.0.21, HEAD',
        homepage: 'http://www.monkey.org/~provos/libevent/'
      })
    end
  end

  describe 'installed?' do
    before do
      expect(shell).to receive(:exec).with('brew info thing') { output }
    end

    context 'is not installed' do
      let(:output) do
        <<-OUTPUT
yaz: stable 4.2.56
http://www.indexdata.com/yaz
Depends on: pkg-config
Not installed
https://github.com/mxcl/homebrew/commits/master/Library/Formula/yaz.rb
        OUTPUT
      end

      specify { expect(subject).to_not be_installed }
    end

    context 'is installed' do
      let(:output) do
        <<-OUTPUT
gdbm: stable 1.10
http://www.gnu.org/software/gdbm/
/usr/local/Cellar/gdbm/1.10 (10 files, 228K) *
https://github.com/mxcl/homebrew/commits/master/Library/Formula/gdbm.rb
==> Options
--universal
	Build a universal binary
        OUTPUT
      end

      specify { expect(subject).to be_installed }
    end
  end

  describe '#installed_versions' do
    before do
      subject.instance_variable_set(:@package_name, 'git')
      expect(shell).to receive(:exec).with('brew info git') { output }
    end

    context 'package not installed' do
      let(:output) do
        <<-OUTPUT
isl: stable 0.11.2, HEAD
http://www.kotnet.org/~skimo/isl/
Not installed
From: https://github.com/mxcl/homebrew/commits/master/Library/Formula/isl.rb
==> Dependencies
Required: gmp
        OUTPUT
      end

      specify { expect(subject.installed_versions).to eq [] }
    end

    context 'package installed' do
      let(:output) do
        <<-OUTPUT
git: stable 1.8.3.4, HEAD
http://git-scm.com
/usr/local/Cellar/git/1.8.3.1 (1324 files, 28M)
  Built from source
/usr/local/Cellar/git/1.8.3.3 (1326 files, 29M)
  Built from source
From: https://github.com/mxcl/homebrew/commits/master/Library/Formula/git.rb
        OUTPUT
      end

      specify { expect(subject.installed_versions).to eq %w[1.8.3.1 1.8.3.3] }
    end
  end

  describe '#install' do
    context 'with version' do
      it 'calls #install_and_switch_version' do
        expect(subject).to receive(:install_and_switch_version).with('0.1.2')

        subject.install('0.1.2')
      end
    end

    context 'no version' do
      context 'failed install' do
        before do
          allow(shell).to receive(:last_exit_status) { 1 }
          expect(shell).to receive(:exec).with('brew install thing')
        end

        specify { expect(subject.install).to eq false }
      end

      context 'successful install' do
        before do
          allow(shell).to receive(:last_exit_status) { 0 }
          expect(shell).to receive(:exec).with('brew install thing')
        end

        specify { expect(subject.install).to eq true }
      end
    end
  end

  describe '#remove' do
    before do
      expect(shell).to receive(:exec).with('brew remove thing')
    end

    context 'failed removal' do
      before { allow(shell).to receive(:last_exit_status) { 1 } }
      specify { expect(subject.remove).to eq false }
    end

    context 'successful removal' do
      before { allow(shell).to receive(:last_exit_status) { 0 } }
      specify { expect(subject.remove).to eq true }
    end
  end

  describe '#upgrade' do
    before do
      expect(shell).to receive(:exec).with('brew upgrade thing')
    end

    context 'failed upgrade' do
      before { allow(shell).to receive(:last_exit_status) { 1 } }
      specify { expect(subject.upgrade).to eq false }
    end

    context 'successful upgrade' do
      before { allow(shell).to receive(:last_exit_status) { 0 } }
      specify { expect(subject.upgrade).to eq true }
    end
  end

  describe '#install_and_switch_version' do
    let(:version_output) do
      <<-OUTPUT
4.2.56   git checkout 9490f3b /usr/local/Library/Formula/thing.rb
1.2.3    git checkout 1234567 /usr/local/Library/Formula/thing.rb
      OUTPUT
    end

    context 'version does not exist' do
      it 'returns false' do
        expect(shell).to receive(:exec).
          with('brew versions thing | grep asdf') { '' }

        expect(subject.send(:install_and_switch_version, 'asdf')).to eq false
      end
    end

    context 'version exists' do
      it 'passes the version to the command' do
        expect(shell).to receive(:exec).with('brew versions thing | grep 1.2.3').
          and_return version_output
        expect(shell).to receive(:exec ).with('brew --prefix') { '/usr/local' }
        expect(shell).to receive(:cd).with('/usr/local')

        expect(shell).to receive(:exec).with('git checkout 1234567 Library/Formula/thing.rb')
        expect(shell).to receive(:last_exit_status).and_return 0
        expect(shell).to receive(:exec).with('brew unlink thing')
        expect(shell).to receive(:last_exit_status).and_return 0
        expect(shell).to receive(:exec).with('brew install thing')
        expect(shell).to receive(:last_exit_status).and_return 0
        expect(shell).to receive(:exec).with('brew switch thing 1.2.3')
        expect(shell).to receive(:last_exit_status).and_return 0
        expect(shell).to receive(:exec).with('git checkout -- Library/Formula/thing.rb')
        expect(shell).to receive(:last_exit_status).and_return 0

        expect(subject.send(:install_and_switch_version, '1.2.3')).to eq true
      end
    end
  end
end
