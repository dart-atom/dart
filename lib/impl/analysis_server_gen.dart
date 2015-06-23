// This is a generated file.

library analysis_server_gen;

class ServerClient {

}

abstract class Domain {
    final ServerClient client;
    final String name;

    Domain(this.client, this.name);

    String toString() => 'Domain ${name}';
}

class ServerDomain extends Domain {
  ServerDomain(ServerClient client) : super(client, 'server');

}

class AnalysisDomain extends Domain {
  AnalysisDomain(ServerClient client) : super(client, 'analysis');

}

class CompletionDomain extends Domain {
  CompletionDomain(ServerClient client) : super(client, 'completion');

}

class SearchDomain extends Domain {
  SearchDomain(ServerClient client) : super(client, 'search');

}

class EditDomain extends Domain {
  EditDomain(ServerClient client) : super(client, 'edit');

}

class ExecutionDomain extends Domain {
  ExecutionDomain(ServerClient client) : super(client, 'execution');

}
