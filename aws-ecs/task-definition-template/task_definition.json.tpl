[
    {
      "name": "${container_name}",
      "image": "${container_image}",
      "memory": ${container_memory},
      "cpu": ${container_cpu},
      "essential": true,
      "executionRoleArn": "${task_execution_role}",
      "portMappings": [
		{
		  "containerPort": ${container_port},
		  "HostPort" : ${container_port},
		  "protocol": "tcp"
		}
      ]
    }
]
