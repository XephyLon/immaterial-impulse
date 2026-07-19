import QtQuick
import QtTest
import "../modules/common/plugins/bundled/docker" as DockerPlugin

TestCase {
    name: "DockerServiceTest"

    function test_parseDockerPs() {
        var docker = DockerPlugin.DockerService;
        verify(docker !== null);

        // docker ps -a --format '{{json .}}' sample output
        var dockerData = 
            '{"ID":"5adc504ae4dd","Names":"odysseus-odysseus-1","State":"exited","Status":"Exited (0) 2 weeks ago"}\n' +
            '{"ID":"ae5ebea00db2","Names":"odysseus-chromadb-1","State":"running","Status":"Up 3 weeks"}\n';

        var parsed = docker.parseDockerPs(dockerData);
        verify(parsed !== null);
        compare(parsed.totalCount, 2);
        compare(parsed.runningCount, 1);
        compare(parsed.containerNames.length, 2);
        compare(parsed.containerNames[0], "odysseus-odysseus-1");
        compare(parsed.containerNames[1], "odysseus-chromadb-1");

        // Test with empty/invalid data
        var invalidData = "invalid data\n{}\n";
        var parsedInvalid = docker.parseDockerPs(invalidData);
        verify(parsedInvalid !== null);
        compare(parsedInvalid.totalCount, 0);
        compare(parsedInvalid.runningCount, 0);
        compare(parsedInvalid.containerNames.length, 0);
    }

    function test_parseInspectAndComposeProjects() {
        var payload = JSON.stringify([{
            Id: "abc123",
            Name: "/web",
            Config: {
                Image: "nginx:latest",
                Labels: {
                    "com.docker.compose.project": "website",
                    "com.docker.compose.service": "web",
                    "com.docker.compose.project.working_dir": "/tmp/website",
                    "com.docker.compose.project.config_files": "compose.yml"
                }
            },
            State: { Status: "running", Running: true, Paused: false, StartedAt: "2026-01-01T00:00:00Z" },
            NetworkSettings: { Ports: { "80/tcp": [{ HostIp: "127.0.0.1", HostPort: "8080" }] } }
        }]);

        var parsed = DockerPlugin.DockerService.parseInspect(payload);
        compare(parsed.containers.length, 1);
        compare(parsed.containers[0].name, "web");
        compare(parsed.containers[0].ports[0], "127.0.0.1:8080 → 80/tcp");
        compare(parsed.composeProjects.length, 1);
        compare(parsed.composeProjects[0].name, "website");
        compare(parsed.composeProjects[0].runningCount, 1);
    }
}
