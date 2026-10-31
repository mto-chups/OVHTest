output "vrack_id" { value = local.vrack_id }
output "network_id" { value = ovh_cloud_project_network_private.this.id }
output "node_network_id" { value = local.node_network_id }
output "data_network_id" { value = local.data_network_id }
output "nodes_subnet_id" { value = ovh_cloud_project_network_private_subnet_v2.nodes.id }
output "load_balancers_subnet_id" { value = ovh_cloud_project_network_private_subnet_v2.load_balancers.id }
output "data_subnet_id" { value = ovh_cloud_project_network_private_subnet_v2.data.id }
output "gateway_id" { value = ovh_cloud_project_gateway.egress.id }
