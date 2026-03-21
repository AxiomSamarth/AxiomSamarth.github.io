---
layout: post
title: Why do K8s CRDs use pointers mostly?
date: '2024-02-24'
description: Why do K8s CRDs use pointers mostly? Custom Resource Definitions (CRDs) in Kubernetes play a crucial role in extending the Kubernetes API to accommodate custom resources and controllers. One interesti…
canonical_url: https://medium.com/@deyagondsamarth/why-do-k8s-crds-use-pointers-mostly-12613b332d83
tags:
- tech
categories:
- kubernetes
medium_original_url: https://medium.com/@deyagondsamarth/why-do-k8s-crds-use-pointers-mostly-12613b332d83
---

<h3>Why do K8s CRDs use pointers mostly?</h3>
<p>Custom Resource Definitions (CRDs) in Kubernetes play a crucial role in extending the Kubernetes API to accommodate custom resources and controllers. One interesting design choice within CRDs is the use of pointer types in the specification (spec) and status (status) section of the resources. <a href="https://github.com/aws-controllers-k8s/ec2-controller/blob/main/apis/v1alpha1/vpc.go" rel="noopener noreferrer">Here</a> is an example CRD of AWS VPC Spec that uses pointers for majority of the Spec fields.</p>
<p>In this blog post, we’ll explore why most Kubernetes CRD specs use pointers and how this design choice enhances flexibility and extensibility.</p>
<h4>The Flexibility of Nullable Fields</h4>
<p>One of the key advantages of using pointers in the spec section is the ability to represent nullable fields. In Go, pointers can be nil, and this characteristic allows us to explicitly indicate when a particular field is absent or not relevant.</p>
<figure><img alt="" src="https://cdn-images-1.medium.com/max/2048/1*ff75ICiQz5f432DZHPsaPw.png" loading="lazy" /></figure>
<p>Here, OptionalField is a pointer to a string, and if left as nil, it signals that the field is not specified. This flexibility is particularly valuable for fields that are optional or conditionally relevant.</p>
<h4>Handling Default Values</h4>
<p>Pointers also help distinguish between a field explicitly set to null and a field that is not set at all. This is crucial when dealing with default values. A nil pointer might mean “use the default value,” while a non-nil pointer indicates an explicitly set value.</p>
<h4>Detecting Changes During Reconciliation</h4>
<p>When reconciling resources, pointers simplify the detection of changes. If a field’s pointer changes from nil to a non-nil value or vice versa, it indicates a modification or an update to that field. This makes it easier for controllers to identify changes in the desired state of the resource.</p>
<h4>Forward Compatibility and Extensibility</h4>
<p>Using pointers in the spec and statussection supports forward compatibility. If new fields are added to the CRD in future versions, existing clients can remain compatible without breaking changes. A nil pointer for a new field would indicate that it is not set, allowing for seamless extensibility.</p>
<figure><img alt="" src="https://cdn-images-1.medium.com/max/2048/1*oZQ4kGeAKRTelC-xWCKZEQ.png" loading="lazy" /></figure>
<p>In this example, the introduction of NewField doesn’t break existing implementations of K8s operators, and clients can choose to set or ignore this new field based on their requirements.</p>
<h4>JSON Serialisation</h4>
<p>Lastly, pointers facilitate natural representation of null values in JSON. When the Go struct is serialised to JSON, a nil pointer becomes a null value in the JSON representation, indicating the absence of the corresponding field.</p>
<h4>Conclusion</h4>
<p>The use of pointer types in the spec and statussection of Kubernetes CRDs provides a powerful mechanism for enhancing flexibility, supporting nullable fields, handling default values, detecting changes during reconciliation, ensuring forward compatibility, and enabling seamless extensibility.</p>
<p>Understanding this design choice is crucial for developers working on Kubernetes operators and custom resources, as it empowers them to create scalable and adaptable systems in the ever-evolving landscape of Kubernetes.</p>
